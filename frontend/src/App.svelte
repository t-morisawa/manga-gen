<script>
  import { generateImage, chat, healthCheck } from './lib/api.js';

  let prompt = '';
  let apiKey = '';
  let imageUrl = '';
  let loading = false;
  let error = '';
  let backendStatus = 'checking...';

  let chatInput = '';
  let chatMessages = [];
  let chatLoading = false;
  let chatError = '';
  let chatApiBaseUrl = 'https://api.openai.com/v1';
  let chatModelName = 'gpt-4o-mini';

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

  async function handleSendChat() {
    if (!chatInput.trim()) return;
    if (!apiKey.trim()) {
      chatError = 'Google API Keyを入力してください / Please enter a Google API Key';
      return;
    }

    const userText = chatInput.trim();
    chatMessages = [...chatMessages, { role: 'user', text: userText }];
    chatInput = '';
    chatLoading = true;
    chatError = '';

    const history = chatMessages
      .slice(0, -1)
      .map(m => ({ role: m.role, text: m.text }));

    try {
      const res = await chat({ message: userText, google_api_key: apiKey, api_base_url: chatApiBaseUrl, model_name: chatModelName, history });
      if (res.success && res.reply) {
        chatMessages = [...chatMessages, { role: 'assistant', text: res.reply }];
      } else {
        chatError = res.error || 'チャットの応答に失敗しました / Chat failed';
      }
    } catch (e) {
      chatError = `通信エラー / Network error: ${e.message}`;
    } finally {
      chatLoading = false;
    }
  }

  function handleChatKeydown(event) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      handleSendChat();
    }
  }

  function clearChat() {
    chatMessages = [];
    chatError = '';
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

  <hr class="divider" />

  <section class="chat-section">
    <h2>LLM Chat / チャット</h2>
    <p class="section-desc">GPT互換API とテキストで対話します / Chat with GPT-compatible API</p>

    <div class="chat-settings">
      <label>
        <span>API Base URL</span>
        <input type="text" bind:value={chatApiBaseUrl} placeholder="https://api.openai.com/v1" />
      </label>
      <label>
        <span>Model Name / モデル名</span>
        <input type="text" bind:value={chatModelName} placeholder="gpt-4o-mini" />
      </label>
    </div>

    <div class="chat-messages">
      {#if chatMessages.length === 0}
        <div class="chat-empty">メッセージを送信してください / Send a message to start</div>
      {/if}
      {#each chatMessages as msg}
        <div class="chat-message {msg.role}">
          <div class="chat-role">{msg.role === 'user' ? 'You' : 'Gemini'}</div>
          <div class="chat-text">{msg.text}</div>
        </div>
      {/each}
      {#if chatLoading}
        <div class="chat-message assistant">
          <div class="chat-role">Gemini</div>
          <div class="chat-text chat-thinking">考え中... / Thinking...</div>
        </div>
      {/if}
    </div>

    {#if chatError}
      <div class="error">{chatError}</div>
    {/if}

    <div class="chat-input-row">
      <textarea
        bind:value={chatInput}
        on:keydown={handleChatKeydown}
        rows="3"
        placeholder="メッセージを入力... / Type a message..."
        disabled={chatLoading}
      ></textarea>
      <div class="chat-buttons">
        <button on:click={handleSendChat} disabled={chatLoading}>
          {chatLoading ? '送信中... / Sending...' : '送信 / Send'}
        </button>
        <button class="btn-secondary" on:click={clearChat} disabled={chatLoading}>
          クリア / Clear
        </button>
      </div>
    </div>
  </section>
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

  .divider {
    margin: 32px 0 24px;
    border: none;
    border-top: 1px solid #e0e0e0;
  }

  .chat-section h2 {
    margin: 0 0 4px;
    font-size: 1.3rem;
    color: #222;
  }

  .section-desc {
    margin: 0 0 16px;
    color: #666;
    font-size: 0.9rem;
  }

  .chat-settings {
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-bottom: 16px;
    padding: 12px;
    background: #f5f5f5;
    border-radius: 8px;
  }

  .chat-settings label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.85rem;
    color: #555;
  }

  .chat-settings input {
    padding: 8px 10px;
    border: 1px solid #ccc;
    border-radius: 6px;
    font-size: 0.9rem;
    outline: none;
    transition: border-color 0.2s;
  }

  .chat-settings input:focus {
    border-color: #1976d2;
  }

  .chat-messages {
    max-height: 400px;
    overflow-y: auto;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 12px;
    margin-bottom: 12px;
    background: #fafafa;
  }

  .chat-empty {
    text-align: center;
    color: #999;
    padding: 24px 0;
    font-size: 0.9rem;
  }

  .chat-message {
    margin-bottom: 12px;
    padding: 10px 12px;
    border-radius: 8px;
    max-width: 85%;
  }

  .chat-message.user {
    margin-left: auto;
    background: #e3f2fd;
  }

  .chat-message.assistant {
    margin-right: auto;
    background: #fff;
    border: 1px solid #e0e0e0;
  }

  .chat-role {
    font-size: 0.75rem;
    font-weight: bold;
    color: #666;
    margin-bottom: 4px;
  }

  .chat-text {
    font-size: 0.95rem;
    color: #222;
    white-space: pre-wrap;
    word-break: break-word;
    line-height: 1.5;
  }

  .chat-thinking {
    color: #999;
    font-style: italic;
  }

  .chat-input-row {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .chat-input-row textarea {
    padding: 10px 12px;
    border: 1px solid #ccc;
    border-radius: 8px;
    font-size: 1rem;
    outline: none;
    resize: vertical;
    font-family: inherit;
    transition: border-color 0.2s;
  }

  .chat-input-row textarea:focus {
    border-color: #1976d2;
  }

  .chat-buttons {
    display: flex;
    gap: 8px;
  }

  .btn-secondary {
    padding: 12px 16px;
    background: #e0e0e0;
    color: #333;
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    cursor: pointer;
    transition: background 0.2s;
  }

  .btn-secondary:hover:not(:disabled) {
    background: #bdbdbd;
  }

  .btn-secondary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
