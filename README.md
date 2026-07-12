# AI Manga Generator (Prototype)

A simple prototype for AI-powered manga image generation using the Gemini API.

This project is inspired by [comic-alpha](../comic-alpha).

## Overview

This is the first step toward a full multi-page manga generation system. It provides:

- A simple Web UI to send image generation prompts to the Gemini API
- Display of generated images in the browser
- Session-ready architecture (to be expanded)

## Tech Stack

- **Frontend:** Svelte + Vite
- **Backend:** Haskell (Scotty + Warp)
- **Image Generation:** Google Gemini API

## Project Structure

```
manga_generator/
├── backend/              # Haskell backend
│   ├── src/Main.hs     # API server
│   ├── static/images/  # Generated images storage
│   └── manga-generator-backend.cabal
├── frontend/           # Svelte frontend
│   ├── src/
│   │   ├── App.svelte
│   │   └── lib/api.js
│   └── vite.config.js
├── README.md           # This file (English)
└── README.ja.md        # Japanese version
```

## Prerequisites

- [GHC](https://www.haskell.org/ghc/) 9.6+ and [cabal-install](https://www.haskell.org/cabal/)
- [Node.js](https://nodejs.org/) 18+ and npm
- A [Google Gemini API key](https://ai.google.dev/)

## Getting Started

### 1. Start the Backend

```bash
cd backend
cabal build
cabal run
```

The backend will start on [http://localhost:5003](http://localhost:5003).

### 2. Start the Frontend

In a new terminal:

```bash
cd frontend
npm install
npm run dev
```

The frontend will start on [http://localhost:5173](http://localhost:5173) (or another port if 5173 is in use).

### 3. Generate an Image

1. Open the frontend URL in your browser.
2. Enter your **Google API Key**.
3. Enter a **prompt** describing the manga image you want.
4. Click **Generate Image**.
5. Wait a few seconds for the image to appear.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/generate-image` | Generate an image via Gemini API |
| GET | `/backend/static/images/:filename` | Serve a generated image |

### POST /api/generate-image

**Request body:**

```json
{
  "prompt": "A cute cat in a manga style",
  "google_api_key": "YOUR_API_KEY"
}
```

**Response:**

```json
{
  "success": true,
  "image_url": "/backend/static/images/xxxx.png"
}
```

## Notes

- Generated images are saved in `backend/static/images/`.
- The backend uses `gemini-2.0-flash-exp-image-generation` by default.
- Make sure your API key has access to Gemini image generation models.

## License

MIT
