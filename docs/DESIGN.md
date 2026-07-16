# 複数ページ漫画生成システム 設計書

## 1. 概要

本設計書は、AI Manga Generatorを「単一画像生成」から「複数ページの漫画生成」へ拡張するための設計を定義する。

### フェーズ分け

| フェーズ | 内容 | 優先度 |
|---------|------|--------|
| Phase 1 | ページ分割・画像生成・一覧表示 | 今回対象 |
| Phase 2 | セリフ・吹き出しの画像合成 | 将来対象 |

## 2. アーキテクチャ

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Frontend   │────▶│   Backend    │────▶│    LLM       │
│  (Svelte)    │◀────│  (Haskell)   │◀────│ (OpenCode Go)│
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │   Gemini     │
                     │   (VLM)      │
                     └──────────────┘
```

### データフロー（逐次生成）

1. **Frontend** が原稿・システムプロンプト・サンプル画像を入力
2. **Backend** が `/api/generate-pages` を受信 → ジョブ作成
3. **Backend** が OpenCode Go (Kimi) に原稿分割を依頼 → JSONを取得
4. **Backend** が JSONをパース・バリデーション
5. **ページ1**: Backend が Gemini にテキストのみで送信 → 画像生成 → 保存
6. **ページ2**: Backend が Gemini に「テキスト + ページ1画像(base64 inline_data)」で送信 → 画像生成 → 保存
7. **ページ3**: Backend が Gemini に「テキスト + ページ2画像」で送信 → ...
8. **Frontend** が `/api/jobs/:id` で進捗をポーリング・一覧表示

**重要**: ページ生成は**逐次（シーケンシャル）**に実行する。前ページの生成画像が確定してから次ページを開始することで、キャラクター・背景・画風の一貫性を保証する。

## 3. JSONスキーマ（原稿分割結果）

### 3.1 基本構造

LLM（Kimi）に生成させるJSONフォーマット。`response_format: {"type": "json_object"}` を使用する。

```json
{
  "metadata": {
    "title": "string",
    "total_pages": "integer",
    "art_style": "string",
    "color_scheme": "string"
  },
  "characters": [
    {
      "id": "string",
      "name": "string",
      "appearance_tags": "string"
    }
  ],
  "pages": [
    {
      "page_number": "integer",
      "reference_mode": "string",
      "scene_time": "string",
      "scene_location": "string",
      "mood": "string",
      "continuity_note": "string",
      "layout_description": "string",
      "full_page_prompt": "string",
      "speech_bubbles": [
        {
          "text": "string",
          "speaker_id": "string"
        }
      ]
    }
  ]
}
```

### 3.2 フィールド定義

#### metadata

| フィールド | 型 | 必須 | 説明 |
|-----------|----|------|------|
| title | string | ○ | 漫画タイトル |
| total_pages | integer | ○ | 総ページ数 |
| art_style | string | ○ | 画風指示（例: "2020年代日本の少女漫画風。きれいな線画、淡い水彩タッチ。"） |
| color_scheme | string | △ | トーン指示（例: "白黒漫画、網トーン多用" または "カラー、パステル調"） |

#### characters

ページをまたいで同一キャラクターの外見を一貫させるための定義。

| フィールド | 型 | 必須 | 説明 |
|-----------|----|------|------|
| id | string | ○ | キャラクター識別子（プロンプト内で使用） |
| name | string | ○ | キャラクター名（管理用） |
| appearance_tags | string | ○ | 画像生成プロンプト用の外見タグ。全ページ共通で挿入される |

#### pages

| フィールド | 型 | 必須 | 説明 |
|-----------|----|------|------|
| page_number | integer | ○ | 1から始まる連番 |
| reference_mode | string | ○ | 前ページ画像の参照方法。 `"none"` / `"previous"` / `"first"` |
| scene_time | string | △ | シーンの時間帯（連続性確保用） |
| scene_location | string | △ | シーンの場所（連続性確保用） |
| mood | string | △ | 感情・雰囲気 |
| continuity_note | string | △ | **最重要**。前ページからの繋がりを記述 |
| layout_description | string | △ | コマ数・読み順などのレイアウト指示 |
| full_page_prompt | string | ○ | **Geminiに渡す実際のプロンプト** |
| speech_bubbles | array | △ | Phase 2用。セリフ一覧（画像合成時に使用） |

**reference_mode の値:**

| 値 | 意味 | 使用ページ |
|----|------|-----------|
| `"none"` | 前ページ画像を参照しない | 1ページ目 |
| `"previous"` | 直前のページ画像をVLM入力に含める | 2ページ目以降（デフォルト） |
| `"first"` | 最初のページ画像を参照する（画風統一用） | 任意 |

### 3.3 continuity_note の重要性

`continuity_note` は前ページの状態を次ページに引き継ぐための**最重要フィールド**。

例:
- `"前ページから花子は全力疾走した後。髪が少し乱れている。制服の緑のカーディガンのボタンが一つ開いている。"`
- `"教室に到着した直後。まだ息が荒い。朝日が窓から差し込んでいる。"`

## 4. API設計（新規・変更）

### 4.1 新規エンドポイント

#### POST `/api/generate-pages`

複数ページ漫画生成のメインエンドポイント。ジョブを作成して非同期実行する。

**Request:**
```json
{
  "manuscript": "string",
  "system_prompt": "string",
  "sample_image_base64": "string (optional)",
  "total_pages": 3,
  "google_api_key": "string",
  "llm_api_key": "string",
  "llm_api_base_url": "string",
  "llm_model_name": "string"
}
```

**Response:**
```json
{
  "success": true,
  "job_id": "uuid",
  "status": "pending"
}
```

内部処理（逐次生成）:
1. ジョブを作成（DB）
2. LLMに原稿分割を依頼（JSON生成）
3. JSONをパース・バリデーション
4. **ページ1**: テキストのみで Gemini に送信 → 画像生成 → 保存 → DB更新
5. **ページ2**: ページ1の画像を `inline_data` として含めて Gemini に送信 → 画像生成 → 保存 → DB更新
6. **ページ3**: ページ2の画像を参照して...（繰り返し）
7. 全ページ完了後、ジョブステータスを `completed` に更新

**処理時間見積もり:**
- 1ページあたり 10〜30秒（モデル・プロンプト長による）
- 3ページの場合: 30〜90秒（並列より遅いが、一貫性が大幅に向上）

#### GET `/api/jobs/:job_id`

ジョブの進捗・結果を取得。

**Response:**
```json
{
  "job_id": "uuid",
  "status": "in_progress",
  "metadata": {
    "title": "...",
    "total_pages": 3
  },
  "pages": [
    {
      "page_number": 1,
      "status": "completed",
      "image_url": "/backend/static/images/xxx.png",
      "prompt": "...",
      "error": null
    },
    {
      "page_number": 2,
      "status": "in_progress",
      "image_url": null,
      "prompt": "...",
      "error": null
    }
  ]
}
```

#### GET `/api/jobs/:job_id/image/:page_number`

特定ページの画像を直接取得（ビューア用）。

#### DELETE `/api/jobs/:job_id`

ジョブと関連画像を削除。

### 4.2 既存エンドポイントの変更

既存の `/api/generate-image` はそのまま残す（単一画像生成も継続使用）。

## 5. バックエンド（Haskell）実装方針

### 5.1 モジュール構成

```
backend/src/
├── Main.hs              # エントリーポイント、ルーティング
├── Types.hs             # 共通型定義（リクエスト/レスポンス/DB）
├── Config.hs            # 設定読み込み
├── LLM.hs               # OpenCode Go / GPT互換API クライアント
├── Gemini.hs            # Gemini API クライアント（既存を整理）
├── PageSplitter.hs      # 原稿分割ロジック（JSON生成・パース・バリデーション）
├── ImageGenerator.hs    # ページごとの画像生成（Geminiへのプロンプト構築）
├── JobQueue.hs          # ジョブ管理（ステータス追跡）
└── Storage.hs           # ファイル保存・画像管理
```

### 5.2 主要な型定義

```haskell
-- 漫画生成ジョブ
data MangaJob = MangaJob
  { jobId :: UUID
  , jobStatus :: JobStatus
  , jobCreatedAt :: UTCTime
  , jobMetadata :: MangaMetadata
  , jobPages :: [PageJob]
  }

data JobStatus = Pending | Splitting | Generating | Completed | Failed

data PageJob = PageJob
  { pageJobNumber :: Int
  , pageJobStatus :: PageStatus
  , pageJobPrompt :: T.Text
  , pageJobImageUrl :: Maybe T.Text
  , pageJobError :: Maybe T.Text
  }

data PageStatus = PagePending | PageInProgress | PageCompleted | PageFailed

-- LLMからの分割結果
data SplitResult = SplitResult
  { splitMetadata :: MangaMetadata
  , splitCharacters :: [CharacterDef]
  , splitPages :: [PageDef]
  }

data PageDef = PageDef
  { pageDefNumber :: Int
  , pageDefReferenceMode :: ReferenceMode
  , pageDefSceneTime :: Maybe T.Text
  , pageDefSceneLocation :: Maybe T.Text
  , pageDefMood :: Maybe T.Text
  , pageDefContinuity :: Maybe T.Text
  , pageDefLayout :: Maybe T.Text
  , pageDefFullPrompt :: T.Text
  , pageDefSpeechBubbles :: [SpeechBubble]
  }

data ReferenceMode = RefNone | RefPrevious | RefFirst
  deriving (Show, Eq)

data SpeechBubble = SpeechBubble
  { sbText :: T.Text
  , sbSpeakerId :: Maybe T.Text
  }

data CharacterDef = CharacterDef
  { charId :: T.Text
  , charName :: T.Text
  , charAppearance :: T.Text
  }

data MangaMetadata = MangaMetadata
  { metaTitle :: T.Text
  , metaTotalPages :: Int
  , metaArtStyle :: T.Text
  , metaColorScheme :: Maybe T.Text
  }
```

### 5.3 原稿分割プロンプト構築（PageSplitter）

```haskell
buildSplitPrompt :: T.Text -> T.Text -> Maybe T.Text -> Int -> T.Text
buildSplitPrompt manuscript systemPrompt sampleImageDesc totalPages =
  T.unlines
    [ "あなたは漫画の脚本家兼プロンプトエンジニアです。"
    , "与えられた原稿を分析し、" <> T.pack (show totalPages) <> "ページの漫画生成プロンプトに分割してください。"
    , ""
    , "【画風・世界観設定】"
    , systemPrompt
    , ""
    , "【原稿】"
    , manuscript
    ]
    <> maybe "" (\desc -> "\n【参考画像の特徴】\n" <> desc <> "\n") sampleImageDesc
    <> T.unlines
    [ ""
    , "【出力形式】"
    , "以下のJSONスキーマに従って出力してください。"
    , "`full_page_prompt` は英語で、画像生成AIに直接渡せる詳細なプロンプトにしてください。"
    , "`continuity_note` には前ページからの状態変化（服装・髪型・表情・場所の変化）を必ず記述してください。"
    , "`reference_mode` は以下のルールで設定してください:"
    , "  - 1ページ目: \"none\""
    , "  - 2ページ目以降: \"previous\"（直前のページ画像を参照して一貫性を保つ）"
    , "  - 画風が不安定になる場合は \"first\"（最初のページを参照）でも可"
    , ""
    , outputSchemaDescription
    ]
```

### 5.4 Geminiプロンプト構築（ImageGenerator）

#### 5.4.1 テキストプロンプト構築

```haskell
buildGeminiPagePrompt :: MangaMetadata -> [CharacterDef] -> PageDef -> T.Text
buildGeminiPagePrompt metadata chars page =
  T.unlines
    [ "Manga illustration, " <> metaArtStyle metadata
    , maybe "" id (metaColorScheme metadata)
    , ""
    , "Characters: " <> T.intercalate "; " (map charAppearance chars)
    , ""
    , maybe "" (\t -> "Scene time: " <> t) (pageDefSceneTime page)
    , maybe "" (\l -> "Location: " <> l) (pageDefSceneLocation page)
    , maybe "" (\m -> "Mood: " <> m) (pageDefMood page)
    , maybe "" (\c -> "Continuity: " <> c) (pageDefContinuity page)
    , maybe "" (\ld -> "Layout: " <> ld) (pageDefLayout page)
    , ""
    , pageDefFullPrompt page
    , ""
    , "No text, no speech bubbles, no captions, no lettering."
    , "Clean manga illustration only."
    ]
```

#### 5.4.2 前ページ画像を参照するGeminiリクエスト構築

ページ2以降では、直前のページ生成画像を `inline_data` としてリクエストに含める。

```haskell
data GeminiPartWithImage = GeminiPartWithImage
  { partText :: Maybe T.Text
  , partInlineData :: Maybe GeminiInlineData
  }

-- | 前ページ画像を読み込んでBase64エンコード
loadReferenceImage :: FilePath -> IO (Either T.Text T.Text)
loadReferenceImage filepath = do
  exists <- doesFileExist filepath
  if not exists
    then return $ Left $ "Reference image not found: " <> T.pack filepath
    else do
      bytes <- B.readFile filepath
      return $ Right $ decodeUtf8 $ Base64.encode bytes

-- | 前ページ画像付きのGeminiコンテンツを構築
buildGeminiContentWithReference :: T.Text -> Maybe T.Text -> [GeminiContent]
buildGeminiContentWithReference promptText (Just base64Image) =
  [ GeminiContent
      { role = Nothing
      , parts =
          [ GeminiPart { text = Just $ "Use the previous page image as a style and character reference. Maintain consistency with character designs, art style, and coloring.\n\n" <> promptText }
          , GeminiPart { text = Nothing }  -- inline_dataは別途JSONシリアライズ時に処理
          ]
      }
  ]
buildGeminiContentWithReference promptText Nothing =
  [ GeminiContent
      { role = Nothing
      , parts = [ GeminiPart { text = Just promptText } ]
      }
  ]
```

**Gemini API リクエスト例（画像参照あり）:**

```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "Use the previous page image as a style and character reference. Maintain consistency with character designs, art style, and coloring.\n\nManga illustration, 2020s shoujo manga style..."
        },
        {
          "inline_data": {
            "mime_type": "image/png",
            "data": "iVBORw0KGgoAAAANSUhEUgAA..."
          }
        }
      ]
    }
  ],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  }
}
```

**実装上の注意:**
- 前ページ画像のBase64サイズが大きい場合、Gemini APIの入力トークン制限に注意
- 参照画像読み込み失敗時はフォールバック: テキストのみで生成（一貫性はやや低下するが処理は継続）
- `reference_mode: "first"` の場合は1ページ目の画像パスを保持しておく必要がある

## 6. フロントエンド実装方針

### 6.1 新規画面

#### 漫画生成フォーム（`/generate`）

- **原稿入力**: テキストエリア（複数行、マークダウン対応でも可）
- **システムプロンプト**: 画風・キャラクター設定用テキストエリア
- **サンプル画像**: ファイルアップロード（任意）
  - 画像をGeminiで分析し、特徴テキストを抽出（Phase 1では手動記述でも可）
- **ページ数**: 数値入力（1〜10くらい）
- **生成ボタン**

#### 進捗・結果表示画面（`/jobs/:id`）

- ジョブステータス表示（進行中 / 完了 / 失敗）
- **ページごとの生成ステータスをリアルタイム表示**
  - 逐次生成なので、ページ1が先に表示され、順次ページ2、3...が追加されていく
  - 各ページ: 待機中 / 生成中 / 完了 / 失敗 のアニメーション表示
- ページごとのサムネイル一覧（グリッドまたはカルーセル）
- 各ページ:
  - 生成画像
  - 使用した参照画像情報（どの前ページを参照したか）
  - プロンプト表示（折りたたみ）
  - 再生成ボタン（個別ページのみ再生成）
  - ダウンロードボタン

**ポーリング戦略:**
```javascript
// 2秒間隔で進捗をポーリング
const pollInterval = setInterval(async () => {
  const job = await getJobStatus(jobId);
  updatePageGrid(job.pages);
  if (job.status === 'completed' || job.status === 'failed') {
    clearInterval(pollInterval);
  }
}, 2000);
```

### 6.2 APIクライアント追加

```javascript
// lib/api.js
export async function generatePages(params) {
  const res = await fetch('/api/generate-pages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  return res.json();
}

export async function getJobStatus(jobId) {
  const res = await fetch(`/api/jobs/${jobId}`);
  return res.json();
}
```

## 7. データベース設計

### 7.1 テーブル

```sql
-- 漫画生成ジョブ
CREATE TABLE manga_jobs (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  title TEXT,
  total_pages INTEGER NOT NULL,
  art_style TEXT,
  color_scheme TEXT,
  manuscript TEXT,
  system_prompt TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  error_message TEXT
);

-- ページ
CREATE TABLE manga_pages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id TEXT NOT NULL,
  page_number INTEGER NOT NULL,
  status TEXT NOT NULL,
  prompt TEXT NOT NULL,
  image_path TEXT,
  reference_image_path TEXT,  -- 前ページ画像パス（VLM入力用。page_number=1はNULL）
  error_message TEXT,
  scene_time TEXT,
  scene_location TEXT,
  mood TEXT,
  continuity_note TEXT,
  layout_description TEXT,
  FOREIGN KEY (job_id) REFERENCES manga_jobs(id)
);

-- キャラクター定義
CREATE TABLE manga_characters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  name TEXT NOT NULL,
  appearance_tags TEXT NOT NULL,
  FOREIGN KEY (job_id) REFERENCES manga_jobs(id)
);

-- セリフ（Phase 2用）
CREATE TABLE manga_speech_bubbles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  page_id INTEGER NOT NULL,
  text TEXT NOT NULL,
  speaker_id TEXT,
  position_x REAL,
  position_y REAL,
  FOREIGN KEY (page_id) REFERENCES manga_pages(id)
);
```

## 8. エラーハンドリング

### 8.1 エラーケース一覧

| エラー | 対応 |
|--------|------|
| LLMのJSON生成失敗（パースエラー） | ジョブをFailedに。エラーメッセージをフロントに返す。リトライボタン提供。 |
| Gemini APIレート制限 | 指数バックオフでリトライ。ジョブステータスはInProgressのまま。 |
| Gemini画像生成失敗 | ページ単位でFailed。他ページは継続。個別再生成ボタン提供。 |
| 前ページ画像読み込み失敗 | **フォールバック**: テキストのみで生成を継続。警告ログを出す。一貫性はやや低下。 |
| タイムアウト | ジョブをFailedに。部分完了分は表示。 |

### 8.2 リトライ戦略

```haskell
-- 指数バックオフリトライ
retryWithBackoff :: Int -> IO (Either T.Text a) -> IO (Either T.Text a)
retryWithBackoff maxRetries action = go 0
  where
    go n
      | n >= maxRetries = return $ Left "Max retries exceeded"
      | otherwise = do
          result <- action
          case result of
            Right val -> return $ Right val
            Left err | isRetryable err -> do
              threadDelay (2 ^ n * 1000000) -- 1s, 2s, 4s, ...
              go (n + 1)
            Left err -> return $ Left err
```

## 9. セキュリティ・運用

### 9.1 現在のまま維持する項目

- APIキーはFrontend→Backendのリクエストボディで送信（DB保存は任意）
- CORS設定は開発環境向けのまま
- 生成画像は `backend/static/images/` に保存

### 9.2 追加検討事項

- ジョブ数の上限（同時実行数制限）
- 古い画像の自動削除
- プロンプト履歴の保持

## 10. 実装順序

1. **Backend**: 型定義 + DBマイグレーション（`reference_image_path` 含む）
2. **Backend**: PageSplitter モジュール（プロンプト構築 + LLM通信 + `reference_mode` 対応）
3. **Backend**: ImageGenerator モジュール（Geminiプロンプト構築 + **前ページ画像 `inline_data` 対応**）
4. **Backend**: JobQueue + 新規エンドポイント実装（**逐次生成ロジック**）
5. **Frontend**: 漫画生成フォームUI
6. **Frontend**: 進捗・結果表示UI（**リアルタイム逐次表示対応**）
7. **統合テスト**

---

*設計書バージョン: 1.1*
*更新日: 2026-07-16*
*変更: 前ページ画像を次ページVLM入力に使う逐次生成フローを追加*

---

*設計書バージョン: 1.0*
*作成日: 2026-07-16*
