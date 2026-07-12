{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Web.Scotty
import Network.Wai.Middleware.Cors (simpleCorsResourcePolicy, CorsResourcePolicy(..), cors)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Network.HTTP.Conduit (httpLbs, parseRequest, RequestBody(RequestBodyLBS), requestBody, requestHeaders, method, responseBody, newManager, tlsManagerSettings)
import Data.Aeson (FromJSON, ToJSON, object, (.=), encode, decode, withObject, (.:), (.:?))
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
import Data.Maybe (fromMaybe, catMaybes, listToMaybe, isJust, isNothing)
import Control.Exception (try, SomeException, displayException)
import Network.HTTP.Conduit (HttpException)

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

-- | Gemini API request body
data GeminiRequest = GeminiRequest
  { contents :: [GeminiContent]
  , generationConfig :: GeminiGenerationConfig
  } deriving (Generic, Show)

instance ToJSON GeminiRequest

data GeminiContent = GeminiContent
  { parts :: [GeminiPart]
  } deriving (Generic, Show)

instance ToJSON GeminiContent

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

-- | Call Gemini API to generate an image
callGeminiImageAPI :: T.Text -> T.Text -> IO (Either T.Text B.ByteString)
callGeminiImageAPI apiKey userPrompt = do
  let model = "gemini-3.1-flash-image-preview"
      url = "https://generativelanguage.googleapis.com/v1beta/models/" ++ T.unpack model ++ ":generateContent?key=" ++ T.unpack apiKey
  
  result <- try $ do
    req <- parseRequest url
    let geminiReq = GeminiRequest
          { contents = [ GeminiContent { parts = [ GeminiPart { text = Just userPrompt } ] } ]
          , generationConfig = GeminiGenerationConfig { responseModalities = ["TEXT", "IMAGE"] }
          }
        body = RequestBodyLBS $ encode geminiReq
        req' = req
          { method = "POST"
          , requestBody = body
          , requestHeaders = [ ("Content-Type", "application/json") ]
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
      Just geminiResp -> do
        let cands = candidates geminiResp
            parts = cands >>= listToMaybe >>= candidateContent >>= contentParts
            imageParts = catMaybes $ fmap inlineData $ fromMaybe [] parts
            textParts = catMaybes $ fmap partText $ fromMaybe [] parts
        
        putStrLn $ "[DEBUG] candidates present: " ++ show (isJust cands)
        putStrLn $ "[DEBUG] textParts count: " ++ show (length textParts)
        putStrLn $ "[DEBUG] imageParts count: " ++ show (length imageParts)
        
        if isNothing cands && null textParts && null imageParts
          then do
            putStrLn $ "[ERROR] Gemini returned error JSON (first 1000 chars): " ++ take 1000 (T.unpack $ decodeUtf8 $ BL.toStrict bodyBytes)
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

  case result of
    Left (e :: SomeException) -> do
      let msg = T.pack $ displayException e
      putStrLn $ "[ERROR] Exception during Gemini API call: " ++ displayException e
      return $ Left msg
    Right inner -> return inner

-- | Save image bytes to file and return relative URL
saveGeneratedImage :: B.ByteString -> IO FilePath
saveGeneratedImage imgBytes = do
  ensureStaticDir
  filename <- generateFilename
  let filepath = staticDir </> filename
  B.writeFile filepath imgBytes
  return $ "/backend/static/images/" ++ filename

main :: IO ()
main = do
  ensureStaticDir
  putStrLn "Starting manga-generator-backend on http://localhost:5003"
  scotty 5003 $ do
    middleware logStdoutDev
    middleware $ cors $ const $ Just simpleCorsResourcePolicy
      { corsOrigins = Just (["http://localhost:5173", "http://localhost:4173", "http://localhost:8000", "http://127.0.0.1:5173"], True)
      , corsMethods = ["GET", "POST", "OPTIONS"]
      , corsRequestHeaders = ["Content-Type"]
      }

    -- Health check
    get "/api/health" $ do
      json $ object ["status" .= ("ok" :: String), "message" .= ("Manga generator API is running" :: String)]

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
