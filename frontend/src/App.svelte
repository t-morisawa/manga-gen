<script>
  import { generateImage, healthCheck } from './lib/api.js';

  let prompt = '';
  let apiKey = '';
  let imageUrl = '';
  let loading = false;
  let error = '';
  let backendStatus = 'checking...';

  // Health check on mount
  healthCheck()
    .then(() => { backendStatus = 'connected'; })
    .catch(() => { backendStatus = 'disconnected'; });

  async function handleGenerate() {
    if (!prompt.trim()) {
      error = 'プロンプトを入力してください / Please enter a prompt';
      return;
    }
    if (!apiKey.trim()) {
      error = 'Google API Keyを入力してください / Please enter a Google API Key';
      return;
    }

    loading = true;
    error = '';
    imageUrl = '';

    try {
      const res = await generateImage({ prompt, google_api_key: apiKey });
      if (res.success && res.image_url) {
        imageUrl = res.image_url;
      } else {
        error = res.error || '画像生成に失敗しました / Image generation failed';
      }
    } catch (e) {
      error = `通信エラー / Network error: ${e.message}`;
    } finally {
      loading = false;
    }
  }
</script>

<main>
  <h1>AI Manga Generator (Prototype)</h1>
  <p class="subtitle">Gemini API 画像生成プロトタイプ / Gemini Image Generation Prototype</p>

  <div class="status-bar">
    Backend: <span class={backendStatus === 'connected' ? 'ok' : 'ng'}>{backendStatus}</span>
  </div>

  <div class="form">
    <label>
      <span>Google API Key</span>
      <input type="password" bind:value={apiKey} placeholder="Enter your Gemini API key" />
    </label>

    <label>
      <span>Prompt / プロンプト</span>
      <textarea bind:value={prompt} rows="6" placeholder="Describe the image you want to generate..."></textarea>
    </label>

    <button on:click={handleGenerate} disabled={loading}>
      {loading ? '生成中... / Generating...' : '画像を生成 / Generate Image'}
    </button>
  </div>

  {#if error}
    <div class="error">{error}</div>
  {/if}

  {#if imageUrl}
    <div class="result">
      <h2>Generated Image</h2>
      <img src={imageUrl} alt="Generated" />
    </div>
  {/if}
</main>

<style>
  :global(body) {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    background: #f5f5f5;
    margin: 0;
    padding: 0;
  }

  main {
    max-width: 720px;
    margin: 40px auto;
    padding: 24px;
    background: #fff;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  }

  h1 {
    margin: 0 0 8px;
    font-size: 1.6rem;
    color: #222;
  }

  .subtitle {
    margin: 0 0 16px;
    color: #666;
    font-size: 0.95rem;
  }

  .status-bar {
    margin-bottom: 16px;
    font-size: 0.85rem;
    color: #444;
  }

  .status-bar .ok { color: #2e7d32; font-weight: bold; }
  .status-bar .ng { color: #c62828; font-weight: bold; }

  .form {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 0.9rem;
    color: #333;
  }

  input, textarea {
    padding: 10px 12px;
    border: 1px solid #ccc;
    border-radius: 8px;
    font-size: 1rem;
    outline: none;
    transition: border-color 0.2s;
  }

  input:focus, textarea:focus {
    border-color: #1976d2;
  }

  button {
    padding: 12px 16px;
    background: #1976d2;
    color: #fff;
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    cursor: pointer;
    transition: background 0.2s;
  }

  button:hover:not(:disabled) {
    background: #1565c0;
  }

  button:disabled {
    background: #90caf9;
    cursor: not-allowed;
  }

  .error {
    margin-top: 14px;
    padding: 10px 12px;
    background: #ffebee;
    color: #c62828;
    border-radius: 8px;
    font-size: 0.95rem;
  }

  .result {
    margin-top: 24px;
  }

  .result h2 {
    margin: 0 0 12px;
    font-size: 1.2rem;
    color: #222;
  }

  .result img {
    width: 100%;
    border-radius: 8px;
    border: 1px solid #ddd;
  }
</style>
