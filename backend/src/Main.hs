{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Web.Scotty
import Network.Wai.Middleware.Cors (simpleCorsResourcePolicy, CorsResourcePolicy(..), cors)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Network.HTTP.Conduit (httpLbs, parseRequest, RequestBody(RequestBodyLBS), requestBody, requestHeaders, method, responseBody, responseTimeout, responseTimeoutMicro, newManager, tlsManagerSettings)
import Data.Aeson (FromJSON, ToJSON, object, (.=), encode, decode, decodeStrict, withObject, (.:), (.:?), (.!=))
import qualified Data.Aeson as Aeson
import GHC.Generics (Generic)
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as B
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import Data.UUID (toString)
import Data.UUID.V4 (nextRandom)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeExtension, (</>))
import Network.HTTP.Types.Status (status400, status500)
import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe, catMaybes, listToMaybe, isNothing, isJust)
import Control.Exception (try, SomeException, displayException)
import Network.HTTP.Conduit (HttpException)
import Database.SQLite.Simple (Connection, open, execute_, execute, query_, query, close)
import qualified Database.SQLite.Simple as SQLite

-- | Request body for image generation
data GenerateImageRequest = GenerateImageRequest
  { prompt :: T.Text
  , googleApiKey :: T.Text
  } deriving (Generic, Show)

instance FromJSON GenerateImageRequest where
  parseJSON = withObject "GenerateImageRequest" $ \v -> GenerateImageRequest
    <$> v .: "prompt"
    <*> v .: "google_api_key"

-- | Response body for image generation
data GenerateImageResponse = GenerateImageResponse
  { success :: Bool
  , imageUrl :: Maybe T.Text
  , errorMessage :: Maybe T.Text
  } deriving (Generic, Show)

instance ToJSON GenerateImageResponse where
  toJSON (GenerateImageResponse s url err) = object $
    [ "success" .= s ]
    ++ catMaybes [ ("image_url" .=) <$> url, ("error" .=) <$> err ]

-- | Request body for chat
data ChatRequest = ChatRequest
  { reqMessage :: T.Text
  , reqApiKey :: T.Text
  , reqApiBaseUrl :: T.Text
  , reqModelName :: T.Text
  , reqImage :: Maybe T.Text
  , reqHistory :: [ChatMessage]
  } deriving (Generic)

instance Show ChatRequest where
  show (ChatRequest msg _ baseUrl modelName img hist) =
    "ChatRequest { message = " ++ show msg ++
    ", apiKey = ***" ++
    ", apiBaseUrl = " ++ show baseUrl ++
    ", modelName = " ++ show modelName ++
    ", image = " ++ show img ++
    ", history = " ++ show (length hist) ++ " items }"

instance FromJSON ChatRequest where
  parseJSON = withObject "ChatRequest" $ \v -> ChatRequest
    <$> v .: "message"
    <*> v .: "google_api_key"
    <*> v .: "api_base_url"
    <*> v .: "model_name"
    <*> v .:? "image"
    <*> v .: "history"

data ChatMessage = ChatMessage
  { chatRole :: T.Text
  , chatText :: T.Text
  , chatImage :: Maybe T.Text
  } deriving (Generic, Show)

instance FromJSON ChatMessage where
  parseJSON = withObject "ChatMessage" $ \v -> ChatMessage
    <$> v .: "role"
    <*> v .: "text"
    <*> v .:? "image"

-- | Response body for chat
data ChatResponse = ChatResponse
  { chatSuccess :: Bool
  , chatReply :: Maybe T.Text
  , chatError :: Maybe T.Text
  } deriving (Generic, Show)

instance ToJSON ChatResponse where
  toJSON (ChatResponse s reply err) = object $
    [ "success" .= s ]
    ++ catMaybes [ ("reply" .=) <$> reply, ("error" .=) <$> err ]

-- ============================================================
-- Split Story (原稿分割) Types
-- ============================================================

-- | Request body for story splitting
data SplitStoryRequest = SplitStoryRequest
  { ssManuscript :: T.Text
  , ssSystemPrompt :: T.Text
  , ssTotalPages :: Int
  , ssApiKey :: T.Text
  , ssApiBaseUrl :: T.Text
  , ssModelName :: T.Text
  } deriving (Generic, Show)

instance FromJSON SplitStoryRequest where
  parseJSON = withObject "SplitStoryRequest" $ \v -> SplitStoryRequest
    <$> v .: "manuscript"
    <*> v .: "system_prompt"
    <*> v .: "total_pages"
    <*> v .: "api_key"
    <*> v .: "api_base_url"
    <*> v .: "model_name"

-- | Response body for story splitting
data SplitStoryResponse = SplitStoryResponse
  { ssrSuccess :: Bool
  , ssrData :: Maybe SplitResult
  , ssrRawJson :: Maybe T.Text
  , ssrError :: Maybe T.Text
  } deriving (Generic, Show)

instance ToJSON SplitStoryResponse where
  toJSON (SplitStoryResponse s mData mRaw mErr) = object $
    [ "success" .= s ]
    ++ catMaybes [ ("data" .=) <$> mData, ("raw_json" .=) <$> mRaw, ("error" .=) <$> mErr ]

-- | Split result from LLM (matches JSON schema in DESIGN.md)
data SplitResult = SplitResult
  { splitMetadata :: MangaMetadata
  , splitCharacters :: [CharacterDef]
  , splitPages :: [PageDef]
  } deriving (Generic, Show)

instance FromJSON SplitResult where
  parseJSON = withObject "SplitResult" $ \v -> SplitResult
    <$> v .: "metadata"
    <*> v .: "characters"
    <*> v .: "pages"

instance ToJSON SplitResult where
  toJSON (SplitResult m cs ps) = object
    [ "metadata" .= m
    , "characters" .= cs
    , "pages" .= ps
    ]

data MangaMetadata = MangaMetadata
  { metaTitle :: T.Text
  , metaTotalPages :: Int
  , metaArtStyle :: T.Text
  , metaColorScheme :: Maybe T.Text
  } deriving (Generic, Show)

instance FromJSON MangaMetadata where
  parseJSON = withObject "MangaMetadata" $ \v -> MangaMetadata
    <$> v .: "title"
    <*> v .: "total_pages"
    <*> v .: "art_style"
    <*> v .:? "color_scheme"

instance ToJSON MangaMetadata where
  toJSON (MangaMetadata t tp a c) = object $
    [ "title" .= t
    , "total_pages" .= tp
    , "art_style" .= a
    ]
    ++ catMaybes [("color_scheme" .=) <$> c]

data CharacterDef = CharacterDef
  { charId :: T.Text
  , charName :: T.Text
  , charAppearance :: T.Text
  } deriving (Generic, Show)

instance FromJSON CharacterDef where
  parseJSON = withObject "CharacterDef" $ \v -> CharacterDef
    <$> v .: "id"
    <*> v .: "name"
    <*> v .: "appearance_tags"

instance ToJSON CharacterDef where
  toJSON (CharacterDef i n a) = object
    [ "id" .= i
    , "name" .= n
    , "appearance_tags" .= a
    ]

data PageDef = PageDef
  { pageDefNumber :: Int
  , pageDefReferenceMode :: T.Text
  , pageDefSceneTime :: Maybe T.Text
  , pageDefSceneLocation :: Maybe T.Text
  , pageDefMood :: Maybe T.Text
  , pageDefContinuity :: Maybe T.Text
  , pageDefLayout :: Maybe T.Text
  , pageDefFullPrompt :: T.Text
  , pageDefSpeechBubbles :: [SpeechBubble]
  } deriving (Generic, Show)

instance FromJSON PageDef where
  parseJSON = withObject "PageDef" $ \v -> PageDef
    <$> v .: "page_number"
    <*> v .: "reference_mode"
    <*> v .:? "scene_time"
    <*> v .:? "scene_location"
    <*> v .:? "mood"
    <*> v .:? "continuity_note"
    <*> v .:? "layout_description"
    <*> v .: "full_page_prompt"
    <*> v .:? "speech_bubbles" .!= []

instance ToJSON PageDef where
  toJSON (PageDef n rm st sl m c l fp sb) = object $
    [ "page_number" .= n
    , "reference_mode" .= rm
    , "full_page_prompt" .= fp
    ]
    ++ catMaybes
      [ ("scene_time" .=) <$> st
      , ("scene_location" .=) <$> sl
      , ("mood" .=) <$> m
      , ("continuity_note" .=) <$> c
      , ("layout_description" .=) <$> l
      , if null sb then Nothing else Just ("speech_bubbles" .= sb)
      ]

data SpeechBubble = SpeechBubble
  { sbText :: T.Text
  , sbSpeakerId :: Maybe T.Text
  } deriving (Generic, Show)

instance FromJSON SpeechBubble where
  parseJSON = withObject "SpeechBubble" $ \v -> SpeechBubble
    <$> v .: "text"
    <*> v .:? "speaker_id"

instance ToJSON SpeechBubble where
  toJSON (SpeechBubble t s) = object $
    [ "text" .= t ]
    ++ catMaybes [("speaker_id" .=) <$> s]

-- ============================================================
-- Gemini API Types
-- ============================================================

-- | Gemini API request body
data GeminiRequest = GeminiRequest
  { contents :: [GeminiContent]
  , generationConfig :: GeminiGenerationConfig
  } deriving (Generic, Show)

instance ToJSON GeminiRequest

data GeminiContent = GeminiContent
  { role :: Maybe T.Text
  , parts :: [GeminiPart]
  } deriving (Generic, Show)

instance ToJSON GeminiContent where
  toJSON (GeminiContent (Just r) ps) = object ["role" .= r, "parts" .= ps]
  toJSON (GeminiContent Nothing ps)  = object ["parts" .= ps]

data GeminiPart = GeminiPart
  { text :: Maybe T.Text
  } deriving (Generic, Show)

instance ToJSON GeminiPart where
  toJSON (GeminiPart (Just t)) = object ["text" .= t]
  toJSON (GeminiPart Nothing)  = object []

data GeminiGenerationConfig = GeminiGenerationConfig
  { responseModalities :: [T.Text]
  } deriving (Generic, Show)

instance ToJSON GeminiGenerationConfig

-- | Gemini API response parsing
data GeminiResponse = GeminiResponse
  { candidates :: Maybe [GeminiCandidate]
  } deriving (Generic, Show)

instance FromJSON GeminiResponse

data GeminiCandidate = GeminiCandidate
  { candidateContent :: Maybe GeminiContentResponse
  } deriving (Generic, Show)

instance FromJSON GeminiCandidate where
  parseJSON = withObject "GeminiCandidate" $ \v -> GeminiCandidate
    <$> v .:? "content"

data GeminiContentResponse = GeminiContentResponse
  { contentParts :: Maybe [GeminiPartResponse]
  } deriving (Generic, Show)

instance FromJSON GeminiContentResponse where
  parseJSON = withObject "GeminiContentResponse" $ \v -> GeminiContentResponse
    <$> v .:? "parts"

data GeminiPartResponse = GeminiPartResponse
  { partText :: Maybe T.Text
  , inlineData :: Maybe GeminiInlineData
  } deriving (Generic, Show)

instance FromJSON GeminiPartResponse where
  parseJSON = withObject "GeminiPartResponse" $ \v -> GeminiPartResponse
    <$> v .:? "text"
    <*> v .:? "inlineData"

data GeminiInlineData = GeminiInlineData
  { mimeType :: T.Text
  , inlineDataData :: T.Text
  } deriving (Generic, Show)

instance FromJSON GeminiInlineData where
  parseJSON = withObject "GeminiInlineData" $ \v -> GeminiInlineData
    <$> v .: "mimeType"
    <*> v .: "data"

-- | Static files directory
staticDir :: FilePath
staticDir = "static" </> "images"

-- | Ensure static directory exists
ensureStaticDir :: IO ()
ensureStaticDir = createDirectoryIfMissing True staticDir

-- | Generate a unique filename
generateFilename :: IO FilePath
generateFilename = do
  uuid <- nextRandom
  return $ toString uuid ++ ".png"

-- | Generic Gemini API call
callGeminiAPI :: T.Text -> T.Text -> [GeminiContent] -> GeminiGenerationConfig -> IO (Either T.Text GeminiResponse)
callGeminiAPI apiKey model contentsList genConfig = do
  let url = "https://generativelanguage.googleapis.com/v1beta/models/" ++ T.unpack model ++ ":generateContent?key=" ++ T.unpack apiKey

  result <- try $ do
    req <- parseRequest url
    let geminiReq = GeminiRequest
          { contents = contentsList
          , generationConfig = genConfig
          }
        body = RequestBodyLBS $ encode geminiReq
        req' = req
          { method = "POST"
          , requestBody = body
          , requestHeaders = [ ("Content-Type", "application/json") ]
          , responseTimeout = responseTimeoutMicro (300 * 1000000)
          }

    manager <- newManager tlsManagerSettings
    response <- httpLbs req' manager

    let bodyBytes = responseBody response
    putStrLn $ "[DEBUG] Gemini response size: " ++ show (BL.length bodyBytes) ++ " bytes"

    case decode bodyBytes of
      Nothing -> do
        putStrLn $ "[ERROR] Failed to parse Gemini JSON response"
        putStrLn $ "[DEBUG] Raw response (first 1000 chars): " ++ take 1000 (T.unpack $ decodeUtf8 $ BL.toStrict bodyBytes)
        return $ Left "Failed to parse Gemini API response"
      Just geminiResp -> return $ Right geminiResp

  case result of
    Left (e :: SomeException) -> do
      let msg = T.pack $ displayException e
      putStrLn $ "[ERROR] Exception during Gemini API call: " ++ displayException e
      return $ Left msg
    Right inner -> return inner

-- | Extract text parts from Gemini response
extractTextParts :: GeminiResponse -> [T.Text]
extractTextParts resp =
  let cands = candidates resp
      parts = cands >>= listToMaybe >>= candidateContent >>= contentParts
  in  catMaybes $ fmap partText $ fromMaybe [] parts

-- | Extract image parts from Gemini response
extractImageParts :: GeminiResponse -> [GeminiInlineData]
extractImageParts resp =
  let cands = candidates resp
      parts = cands >>= listToMaybe >>= candidateContent >>= contentParts
  in  catMaybes $ fmap inlineData $ fromMaybe [] parts

-- | Call Gemini API to generate an image
callGeminiImageAPI :: T.Text -> T.Text -> IO (Either T.Text B.ByteString)
callGeminiImageAPI apiKey userPrompt = do
  let model = "gemini-3.1-flash-image-preview"
      contentsList = [ GeminiContent { role = Nothing, parts = [ GeminiPart { text = Just userPrompt } ] } ]
      genConfig = GeminiGenerationConfig { responseModalities = ["TEXT", "IMAGE"] }

  result <- callGeminiAPI apiKey model contentsList genConfig
  case result of
    Left err -> return $ Left err
    Right geminiResp -> do
      let textParts = extractTextParts geminiResp
          imageParts = extractImageParts geminiResp

      putStrLn $ "[DEBUG] textParts count: " ++ show (length textParts)
      putStrLn $ "[DEBUG] imageParts count: " ++ show (length imageParts)

      if isNothing (candidates geminiResp) && null textParts && null imageParts
        then do
          putStrLn $ "[ERROR] Gemini returned error JSON"
          return $ Left "Gemini API returned an error. Check logs for details."
        else case listToMaybe imageParts of
          Nothing -> do
            let reason = fromMaybe "No image generated" (listToMaybe textParts)
            putStrLn $ "[ERROR] No image in Gemini response: " ++ T.unpack reason
            return $ Left reason
          Just inline -> do
            let base64Data = inlineDataData inline
            case Base64.decode (encodeUtf8 base64Data) of
              Left err -> do
                putStrLn $ "[ERROR] Base64 decode failed: " ++ err
                return $ Left $ T.pack $ "Base64 decode error: " ++ err
              Right imgBytes -> do
                putStrLn $ "[INFO] Image decoded: " ++ show (B.length imgBytes) ++ " bytes"
                return $ Right imgBytes

-- | Call GPT-compatible API for text chat
callChatAPI :: T.Text -> T.Text -> T.Text -> T.Text -> Maybe T.Text -> [ChatMessage] -> Maybe Aeson.Value -> IO (Either T.Text T.Text)
callChatAPI apiKey apiBaseUrl modelName userMessage userImage history responseFormat = do
  let url = T.unpack $ apiBaseUrl <> "/chat/completions"

  result <- try $ do
    req <- parseRequest url
    let currentUserMsg = ChatMessage "user" userMessage userImage
        allMessages = history ++ [currentUserMsg]
        gptReq = GPTChatRequest
          { gptModel = modelName
          , gptMessages = map msgToGPT allMessages
          , gptResponseFormat = responseFormat
          }
        body = RequestBodyLBS $ encode gptReq
        req' = req
          { method = "POST"
          , requestBody = body
          , requestHeaders =
              [ ("Content-Type", "application/json")
              , ("Authorization", "Bearer " <> encodeUtf8 apiKey)
              ]
          , responseTimeout = responseTimeoutMicro (300 * 1000000)
          }

    manager <- newManager tlsManagerSettings
    response <- httpLbs req' manager

    let bodyBytes = responseBody response
    putStrLn $ "[DEBUG] Chat API response size: " ++ show (BL.length bodyBytes) ++ " bytes"

    case decode bodyBytes of
      Nothing -> do
        putStrLn $ "[ERROR] Failed to parse Chat API JSON response"
        putStrLn $ "[DEBUG] Raw response (first 1000 chars): " ++ take 1000 (T.unpack $ decodeUtf8 $ BL.toStrict bodyBytes)
        return $ Left "Failed to parse Chat API response"
      Just (gptResp :: GPTChatResponse) -> do
        case gptChoices gptResp of
          [] -> do
            putStrLn $ "[ERROR] No choices in Chat API response"
            return $ Left "No response from API"
          (choice:_) -> do
            let replyText = gptResponseContent $ gptMessage choice
            putStrLn $ "[INFO] Chat reply length: " ++ show (T.length replyText)
            return $ Right replyText

  case result of
    Left (e :: SomeException) -> do
      let msg = T.pack $ displayException e
      putStrLn $ "[ERROR] Exception during Chat API call: " ++ displayException e
      return $ Left msg
    Right inner -> return inner
  where
    msgToGPT :: ChatMessage -> GPTMessage
    msgToGPT msg = case chatImage msg of
      Nothing -> GPTMessage (chatRole msg) (GPTContentText (chatText msg))
      Just imgBase64 ->
        let imgDataUrl = "data:image/png;base64," <> imgBase64
            parts =
              [ GPTContentPart "text" (Just (chatText msg)) Nothing
              , GPTContentPart "image_url" Nothing (Just (GPTImageUrl imgDataUrl))
              ]
        in  GPTMessage (chatRole msg) (GPTContentParts parts)

-- ============================================================
-- Split Story Functions
-- ============================================================

-- | Build the prompt for story splitting LLM call
buildSplitPrompt :: T.Text -> T.Text -> Int -> T.Text
buildSplitPrompt manuscript systemPrompt totalPages =
  T.unlines
    [ "You are a manga scriptwriter and prompt engineer."
    , "Analyze the given manuscript and split it into " <> T.pack (show totalPages) <> " manga page generation prompts."
    , ""
    , "【Art Style / World Setting】"
    , systemPrompt
    , ""
    , "【Manuscript】"
    , manuscript
    , ""
    , "【Output Rules】"
    , "Output JSON following this exact schema."
    , "- `full_page_prompt` must be detailed English prompt directly usable by an image generation AI."
    , "- `continuity_note` must describe state changes from previous page (clothing, hairstyle, expression, location)."
    , "- `reference_mode`: first page = \"none\", subsequent pages = \"previous\"."
    , "- `speech_bubbles` should contain dialog text and speaker_id for each page."
    , "- Characters defined in `characters` array with `id`, `name`, and `appearance_tags` for consistency."
    , ""
    , "【JSON Schema】"
    , "{"
    , "  \"metadata\": {"
    , "    \"title\": \"...\","
    , "    \"total_pages\": N,"
    , "    \"art_style\": \"...\","
    , "    \"color_scheme\": \"...\""
    , "  },"
    , "  \"characters\": ["
    , "    { \"id\": \"...\", \"name\": \"...\", \"appearance_tags\": \"...\" }"
    , "  ],"
    , "  \"pages\": ["
    , "    {"
    , "      \"page_number\": N,"
    , "      \"reference_mode\": \"none|previous|first\","
    , "      \"scene_time\": \"...\","
    , "      \"scene_location\": \"...\","
    , "      \"mood\": \"...\","
    , "      \"continuity_note\": \"...\","
    , "      \"layout_description\": \"...\","
    , "      \"full_page_prompt\": \"...\","
    , "      \"speech_bubbles\": ["
    , "        { \"text\": \"...\", \"speaker_id\": \"...\" }"
    , "      ]"
    , "    }"
    , "  ]"
    , "}"
    , ""
    , "Output ONLY the JSON. No markdown, no explanation."
    ]

-- | Call LLM to split manuscript and parse the result
callSplitAPI :: T.Text -> T.Text -> T.Text -> T.Text -> T.Text -> Int -> IO (Either T.Text (SplitResult, T.Text))
callSplitAPI apiKey apiBaseUrl modelName manuscript systemPrompt totalPages = do
  let prompt = buildSplitPrompt manuscript systemPrompt totalPages
      responseFormat = Just $ Aeson.object
        [ "type" .= ("json_object" :: T.Text)
        ]

  -- Call chat API with JSON mode
  result <- callChatAPI apiKey apiBaseUrl modelName prompt Nothing [] responseFormat
  case result of
    Left err -> return $ Left err
    Right rawJson -> do
      putStrLn $ "[DEBUG] Raw split response (first 500 chars): " ++ take 500 (T.unpack rawJson)
      -- Try to parse the JSON
      case Aeson.decodeStrict (encodeUtf8 rawJson) :: Maybe SplitResult of
        Nothing -> do
          putStrLn $ "[ERROR] Failed to parse split result JSON"
          return $ Left $ "Failed to parse LLM response as JSON. Raw: " <> T.take 200 rawJson
        Just splitResult -> do
          putStrLn $ "[INFO] Successfully parsed split result: " ++ show (length $ splitPages splitResult) ++ " pages"
          return $ Right (splitResult, rawJson)

-- ============================================================
-- GPT-compatible API Types
data GPTChatRequest = GPTChatRequest
  { gptModel :: T.Text
  , gptMessages :: [GPTMessage]
  , gptResponseFormat :: Maybe Aeson.Value
  } deriving (Generic, Show)

instance ToJSON GPTChatRequest where
  toJSON (GPTChatRequest model msgs mFmt) =
    case mFmt of
      Nothing -> object ["model" .= model, "messages" .= msgs]
      Just fmt -> object ["model" .= model, "messages" .= msgs, "response_format" .= fmt]

data GPTMessage = GPTMessage
  { gptRole :: T.Text
  , gptContent :: GPTContent
  } deriving (Generic, Show)

data GPTContent
  = GPTContentText T.Text
  | GPTContentParts [GPTContentPart]
  deriving (Generic, Show)

instance ToJSON GPTContent where
  toJSON (GPTContentText t) = Aeson.toJSON t
  toJSON (GPTContentParts parts) = Aeson.toJSON parts

data GPTContentPart = GPTContentPart
  { partType :: T.Text
  , gptPartText :: Maybe T.Text
  , partImageUrl :: Maybe GPTImageUrl
  } deriving (Generic, Show)

instance ToJSON GPTContentPart where
  toJSON (GPTContentPart "text" (Just t) _) =
    object ["type" .= ("text" :: T.Text), "text" .= t]
  toJSON (GPTContentPart "image_url" _ (Just url)) =
    object ["type" .= ("image_url" :: T.Text), "image_url" .= url]
  toJSON _ = object []

data GPTImageUrl = GPTImageUrl
  { imageUrlUrl :: T.Text
  } deriving (Generic, Show)

instance ToJSON GPTImageUrl where
  toJSON (GPTImageUrl u) = object ["url" .= u]

instance ToJSON GPTMessage where
  toJSON (GPTMessage r c) = object ["role" .= r, "content" .= c]

-- | GPT-compatible API response types
data GPTChatResponse = GPTChatResponse
  { gptChoices :: [GPTChoice]
  } deriving (Show)

instance FromJSON GPTChatResponse where
  parseJSON = withObject "GPTChatResponse" $ \v -> GPTChatResponse
    <$> v .: "choices"

data GPTChoice = GPTChoice
  { gptMessage :: GPTResponseMessage
  } deriving (Show)

instance FromJSON GPTChoice where
  parseJSON = withObject "GPTChoice" $ \v -> GPTChoice
    <$> v .: "message"

data GPTResponseMessage = GPTResponseMessage
  { gptResponseContent :: T.Text
  } deriving (Show)

instance FromJSON GPTResponseMessage where
  parseJSON = withObject "GPTResponseMessage" $ \v -> GPTResponseMessage
    <$> v .: "content"

-- | Save image bytes to file and return relative URL
saveGeneratedImage :: B.ByteString -> IO FilePath
saveGeneratedImage imgBytes = do
  ensureStaticDir
  filename <- generateFilename
  let filepath = staticDir </> filename
  B.writeFile filepath imgBytes
  return $ "/backend/static/images/" ++ filename

dbPath :: FilePath
dbPath = "manga_gen.db"

initDB :: IO Connection
initDB = do
  conn <- open dbPath
  execute_ conn "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
  return conn

data SettingsRequest = SettingsRequest
  { setGoogleApiKey :: Maybe T.Text
  , setChatApiKey :: Maybe T.Text
  , setChatApiBaseUrl :: Maybe T.Text
  , setChatModelName :: Maybe T.Text
  } deriving (Generic, Show)

instance FromJSON SettingsRequest where
  parseJSON = withObject "SettingsRequest" $ \v -> SettingsRequest
    <$> v .:? "google_api_key"
    <*> v .:? "chat_api_key"
    <*> v .:? "chat_api_base_url"
    <*> v .:? "chat_model_name"

instance ToJSON SettingsRequest where
  toJSON (SettingsRequest g c cb m) = object $
    catMaybes
      [ ("google_api_key" .=) <$> g
      , ("chat_api_key" .=) <$> c
      , ("chat_api_base_url" .=) <$> cb
      , ("chat_model_name" .=) <$> m
      ]

data SettingsResponse = SettingsResponse
  { resGoogleApiKey :: T.Text
  , resChatApiKey :: T.Text
  , resChatApiBaseUrl :: T.Text
  , resChatModelName :: T.Text
  } deriving (Generic, Show)

instance ToJSON SettingsResponse where
  toJSON (SettingsResponse g c cb m) = object
    [ "google_api_key" .= g
    , "chat_api_key" .= c
    , "chat_api_base_url" .= cb
    , "chat_model_name" .= m
    ]

getSetting :: Connection -> T.Text -> IO T.Text
getSetting conn key = do
  rows <- query conn "SELECT value FROM settings WHERE key = ?" (SQLite.Only key) :: IO [(SQLite.Only T.Text)]
  case rows of
    ((SQLite.Only val):_) -> return val
    [] -> return ""

setSetting :: Connection -> T.Text -> T.Text -> IO ()
setSetting conn key val = do
  execute conn "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)" (key, val)

getAllSettings :: Connection -> IO SettingsResponse
getAllSettings conn = do
  g <- getSetting conn "google_api_key"
  c <- getSetting conn "chat_api_key"
  cb <- getSetting conn "chat_api_base_url"
  m <- getSetting conn "chat_model_name"
  return $ SettingsResponse g c cb m

saveSettings :: Connection -> SettingsRequest -> IO ()
saveSettings conn (SettingsRequest g c cb m) = do
  maybe (return ()) (setSetting conn "google_api_key") g
  maybe (return ()) (setSetting conn "chat_api_key") c
  maybe (return ()) (setSetting conn "chat_api_base_url") cb
  maybe (return ()) (setSetting conn "chat_model_name") m

main :: IO ()
main = do
  ensureStaticDir
  conn <- initDB
  putStrLn "Starting manga-generator-backend on http://localhost:5003"
  scotty 5003 $ do
    middleware logStdoutDev
    middleware $ cors $ const $ Just simpleCorsResourcePolicy
      { corsOrigins = Just (["http://localhost:5173", "http://localhost:4173", "http://localhost:8000", "http://127.0.0.1:5173"], True)
      , corsMethods = ["GET", "POST", "OPTIONS"]
      , corsRequestHeaders = ["Content-Type"]
      }

    get "/api/health" $ do
      json $ object ["status" .= ("ok" :: String), "message" .= ("Manga generator API is running" :: String)]

    get "/api/settings" $ do
      settings <- liftIO $ getAllSettings conn
      json settings

    post "/api/settings" $ do
      reqBody <- body
      case decode reqBody of
        Nothing -> do
          liftIO $ putStrLn "[ERROR] Invalid JSON for settings"
          status status400
          json $ object ["error" .= ("Invalid JSON" :: String)]
        Just settingsReq -> do
          liftIO $ saveSettings conn settingsReq
          liftIO $ putStrLn "[INFO] Settings saved"
          json $ object ["success" .= True]

    -- Generate image endpoint
    post "/api/generate-image" $ do
      reqBody <- body
      case decode reqBody of
        Nothing -> do
          liftIO $ putStrLn "[ERROR] Invalid JSON request body"
          status status400
          json $ GenerateImageResponse False Nothing (Just "Invalid JSON request body")
        Just (GenerateImageRequest {..}) -> do
          liftIO $ putStrLn $ "[INFO] Generating image with prompt length: " ++ show (T.length prompt)
          result <- liftIO $ try $ callGeminiImageAPI googleApiKey prompt
          case result of
            Left (e :: SomeException) -> do
              let msg = T.pack $ displayException e
              liftIO $ putStrLn $ "[ERROR] Unhandled exception in handler: " ++ displayException e
              status status500
              json $ GenerateImageResponse False Nothing (Just msg)
            Right (Left err) -> do
              liftIO $ putStrLn $ "[ERROR] Gemini returned error: " ++ T.unpack err
              status status500
              json $ GenerateImageResponse False Nothing (Just err)
            Right (Right imgBytes) -> do
              imagePath <- liftIO $ saveGeneratedImage imgBytes
              liftIO $ putStrLn $ "[INFO] Image saved: " ++ imagePath
              json $ GenerateImageResponse True (Just $ T.pack imagePath) Nothing

    -- Chat endpoint
    post "/api/chat" $ do
      reqBody <- body
      case decode reqBody of
        Nothing -> do
          liftIO $ putStrLn "[ERROR] Invalid JSON request body for chat"
          status status400
          json $ ChatResponse False Nothing (Just "Invalid JSON request body")
        Just (ChatRequest {..}) -> do
          liftIO $ putStrLn $ "[INFO] Chat request, message length: " ++ show (T.length reqMessage) ++ ", model: " ++ T.unpack reqModelName ++ ", hasImage: " ++ show (isJust reqImage) ++ ", history: " ++ show (length reqHistory)
          result <- liftIO $ try $ callChatAPI reqApiKey reqApiBaseUrl reqModelName reqMessage reqImage reqHistory Nothing
          case result of
            Left (e :: SomeException) -> do
              let msg = T.pack $ displayException e
              liftIO $ putStrLn $ "[ERROR] Unhandled exception in chat handler: " ++ displayException e
              status status500
              json $ ChatResponse False Nothing (Just msg)
            Right (Left err) -> do
              liftIO $ putStrLn $ "[ERROR] Chat API returned error: " ++ T.unpack err
              status status500
              json $ ChatResponse False Nothing (Just err)
            Right (Right replyText) -> do
              liftIO $ putStrLn $ "[INFO] Chat reply sent, length: " ++ show (T.length replyText)
              json $ ChatResponse True (Just replyText) Nothing

    -- Split story endpoint
    post "/api/split-story" $ do
      reqBody <- body
      case decode reqBody of
        Nothing -> do
          liftIO $ putStrLn "[ERROR] Invalid JSON request body for split-story"
          status status400
          json $ SplitStoryResponse False Nothing Nothing (Just "Invalid JSON request body")
        Just (SplitStoryRequest {..}) -> do
          liftIO $ putStrLn $ "[INFO] Split story request, manuscript length: " ++ show (T.length ssManuscript) ++ ", pages: " ++ show ssTotalPages ++ ", model: " ++ T.unpack ssModelName
          result <- liftIO $ try $ callSplitAPI ssApiKey ssApiBaseUrl ssModelName ssManuscript ssSystemPrompt ssTotalPages
          case result of
            Left (e :: SomeException) -> do
              let msg = T.pack $ displayException e
              liftIO $ putStrLn $ "[ERROR] Unhandled exception in split-story handler: " ++ displayException e
              status status500
              json $ SplitStoryResponse False Nothing Nothing (Just msg)
            Right (Left err) -> do
              liftIO $ putStrLn $ "[ERROR] Split API returned error: " ++ T.unpack err
              status status500
              json $ SplitStoryResponse False Nothing Nothing (Just err)
            Right (Right (splitResult, rawJson)) -> do
              liftIO $ putStrLn $ "[INFO] Split story success: " ++ show (length $ splitPages splitResult) ++ " pages"
              json $ SplitStoryResponse True (Just splitResult) (Just rawJson) Nothing

    -- Serve generated images
    get "/backend/static/images/:filename" $ do
      filename <- captureParam "filename"
      let filepath = staticDir </> filename
      exists <- liftIO $ doesFileExist filepath
      if exists
        then do
          setHeader "Content-Type" "image/png"
          file filepath
        else do
          status status400
          Web.Scotty.text "Image not found"
