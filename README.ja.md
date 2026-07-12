# AI漫画ジェネレーター（プロトタイプ）

Gemini APIを使ったAI画像生成プロトタイプです。

[comic-alpha](../comic-alpha) を参考にしています。

## 概要

これは複数ページの漫画自動生成システムの第一ステップです。現時点で提供する機能は以下の通りです。

- シンプルなWeb UIからGemini APIに画像生成プロンプトを送信
- ブラウザ上で生成された画像を表示
- 将来的なセッション管理に向けたアーキテクチャ

## 技術スタック

- **フロントエンド:** Svelte + Vite
- **バックエンド:** Haskell (Scotty + Warp)
- **画像生成:** Google Gemini API

## プロジェクト構成

```
manga_generator/
├── backend/              # Haskellバックエンド
│   ├── src/Main.hs     # APIサーバー
│   ├── static/images/  # 生成画像の保存先
│   └── manga-generator-backend.cabal
├── frontend/           # Svelteフロントエンド
│   ├── src/
│   │   ├── App.svelte
│   │   └── lib/api.js
│   └── vite.config.js
├── README.md           # 英語版
└── README.ja.md        # このファイル（日本語版）
```

## 必要条件

- [GHC](https://www.haskell.org/ghc/) 9.6+ と [cabal-install](https://www.haskell.org/cabal/)
- [Node.js](https://nodejs.org/) 18+ と npm
- [Google Gemini APIキー](https://ai.google.dev/)

## 起動方法

### 1. バックエンドを起動する

```bash
cd backend
cabal build
cabal run
```

バックエンドは [http://localhost:5003](http://localhost:5003) で起動します。

### 2. フロントエンドを起動する

別のターミナルで:

```bash
cd frontend
npm install
npm run dev
```

フロントエンドは [http://localhost:5173](http://localhost:5173) で起動します（5173番ポートが使用中の場合は別のポートが選ばれます）。

### 3. 画像を生成する

1. ブラウザでフロントエンドのURLを開きます。
2. **Google API Key** を入力します。
3. 生成したい漫画画像の **プロンプト** を入力します。
4. **画像を生成** ボタンをクリックします。
5. 数秒待つと、生成された画像が表示されます。

## APIエンドポイント

| メソッド | エンドポイント | 説明 |
|--------|----------|-------------|
| GET | `/api/health` | ヘルスチェック |
| POST | `/api/generate-image` | Gemini API経由で画像を生成 |
| GET | `/backend/static/images/:filename` | 生成された画像を配信 |

### POST /api/generate-image

**リクエスト本文:**

```json
{
  "prompt": "A cute cat in a manga style",
  "google_api_key": "YOUR_API_KEY"
}
```

**レスポンス:**

```json
{
  "success": true,
  "image_url": "/backend/static/images/xxxx.png"
}
```

## 注意事項

- 生成された画像は `backend/static/images/` に保存されます。
- バックエンドはデフォルトで `gemini-2.0-flash-exp-image-generation` を使用します。
- APIキーにGemini画像生成モデルへのアクセス権限があることを確認してください。

## ライセンス

MIT
