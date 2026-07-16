<script>
  import { generateImage, chat, splitStory, healthCheck, getSettings, saveSettings } from './lib/api.js';

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
  let chatApiKey = '';
  let chatApiBaseUrl = 'https://api.openai.com/v1';
  let chatModelName = 'gpt-4o-mini';
  let chatImageFile = null;
  let chatImageBase64 = '';
  let chatImagePreview = '';
  let settingsSaved = false;

  healthCheck()
    .then(() => { backendStatus = 'connected'; })
    .catch(() => { backendStatus = 'disconnected'; });

  getSettings().then(s => {
    if (s.google_api_key) apiKey = s.google_api_key;
    if (s.chat_api_key) chatApiKey = s.chat_api_key;
    if (s.chat_api_base_url) chatApiBaseUrl = s.chat_api_base_url;
    if (s.chat_model_name) chatModelName = s.chat_model_name;
  }).catch(() => {});

  async function handleSaveSettings() {
    try {
      await saveSettings({
        google_api_key: apiKey,
        chat_api_key: chatApiKey,
        chat_api_base_url: chatApiBaseUrl,
        chat_model_name: chatModelName,
      });
      settingsSaved = true;
      setTimeout(() => { settingsSaved = false; }, 2000);
    } catch (e) {
      console.error('Failed to save settings', e);
    }
  }

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
    if (!chatInput.trim() && !chatImageBase64) return;
    if (!chatApiKey.trim()) {
      chatError = 'APIキーを入力してください / Please enter an API Key';
      return;
    }

    const userText = chatInput.trim();
    const userImage = chatImageBase64 || null;
    chatMessages = [...chatMessages, { role: 'user', text: userText, image: chatImagePreview || null }];
    chatInput = '';
    chatImageFile = null;
    chatImageBase64 = '';
    chatImagePreview = '';
    chatLoading = true;
    chatError = '';

    const history = chatMessages
      .slice(0, -1)
      .map(m => ({ role: m.role, text: m.text }));

    try {
      const res = await chat({ message: userText, google_api_key: chatApiKey, api_base_url: chatApiBaseUrl, model_name: chatModelName, image: userImage, history });
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

  function handleImageSelect(event) {
    const file = event.target.files[0];
    if (!file) return;

    chatImageFile = file;
    const reader = new FileReader();
    reader.onload = (e) => {
      const dataUrl = e.target.result;
      chatImagePreview = dataUrl;
      const base64Part = dataUrl.split(',')[1];
      chatImageBase64 = base64Part;
    };
    reader.readAsDataURL(file);
  }

  function clearChatImage() {
    chatImageFile = null;
    chatImageBase64 = '';
    chatImagePreview = '';
  }

  function clearChat() {
    chatMessages = [];
    chatError = '';
    clearChatImage();
  }

  // ── Story Splitter state ──
  let ssManuscript = '';
  let ssSystemPrompt = '';
  let ssTotalPages = 3;
  let ssLoading = false;
  let ssError = '';
  let ssResult = null;
  let ssRawJson = '';
  let ssShowRaw = false;

  async function handleSplitStory() {
    if (!ssManuscript.trim()) {
      ssError = '原稿を入力してください / Please enter a manuscript';
      return;
    }
    if (!chatApiKey.trim()) {
      ssError = 'Chat API Keyを入力してください / Please enter a Chat API Key';
      return;
    }

    ssLoading = true;
    ssError = '';
    ssResult = null;
    ssRawJson = '';

    try {
      const res = await splitStory({
        manuscript: ssManuscript,
        system_prompt: ssSystemPrompt,
        total_pages: ssTotalPages,
        api_key: chatApiKey,
        api_base_url: chatApiBaseUrl,
        model_name: chatModelName,
      });
      if (res.success && res.data && res.data.metadata) {
        ssResult = res.data;
        ssRawJson = res.raw_json || '';
      } else if (res.success) {
        ssError = 'レスポンスにデータがありません / Response missing data';
      } else {
        ssError = res.error || '原稿分割に失敗しました / Story splitting failed';
      }
    } catch (e) {
      ssError = `通信エラー / Network error: ${e.message}`;
    } finally {
      ssLoading = false;
    }
  }
</script>

<main>
  <h1>AI Manga Generator (Prototype)</h1>
  <p class="subtitle">Gemini API 画像生成プロトタイプ / Gemini Image Generation Prototype</p>

  <div class="status-bar">
    Backend: <span class={backendStatus === 'connected' ? 'ok' : 'ng'}>{backendStatus}</span>
  </div>

  <div class="settings-panel">
    <div class="settings-header">
      <h3>API Settings / API設定</h3>
      <button class="btn-save-settings" on:click={handleSaveSettings}>
        {settingsSaved ? '保存済み / Saved!' : '設定を保存 / Save Settings'}
      </button>
    </div>
    <div class="settings-fields">
      <label>
        <span>Google API Key (画像生成用)</span>
        <input type="password" bind:value={apiKey} placeholder="Gemini API key" />
      </label>
      <label>
        <span>Chat API Key</span>
        <input type="password" bind:value={chatApiKey} placeholder="sk-..." />
      </label>
      <label>
        <span>Chat API Base URL</span>
        <input type="text" bind:value={chatApiBaseUrl} placeholder="https://api.openai.com/v1" />
      </label>
      <label>
        <span>Chat Model Name</span>
        <input type="text" bind:value={chatModelName} placeholder="gpt-4o-mini" />
      </label>
    </div>
  </div>

  <div class="form">
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

    <div class="chat-messages">
      {#if chatMessages.length === 0}
        <div class="chat-empty">メッセージを送信してください / Send a message to start</div>
      {/if}
      {#each chatMessages as msg}
        <div class="chat-message {msg.role}">
          <div class="chat-role">{msg.role === 'user' ? 'You' : 'AI'}</div>
          {#if msg.image}
            <img src={msg.image} alt="Uploaded" class="chat-image" />
          {/if}
          {#if msg.text}
            <div class="chat-text">{msg.text}</div>
          {/if}
        </div>
      {/each}
      {#if chatLoading}
        <div class="chat-message assistant">
          <div class="chat-role">AI</div>
          <div class="chat-text chat-thinking">考え中... / Thinking...</div>
        </div>
      {/if}
    </div>

    {#if chatError}
      <div class="error">{chatError}</div>
    {/if}

    <div class="chat-input-row">
      {#if chatImagePreview}
        <div class="chat-image-preview">
          <img src={chatImagePreview} alt="Preview" />
          <button class="btn-remove-image" on:click={clearChatImage}>×</button>
        </div>
      {/if}
      <div class="chat-input-controls">
        <label class="btn-upload">
          <input type="file" accept="image/*" on:change={handleImageSelect} disabled={chatLoading} />
          画像を追加 / Add Image
        </label>
        <textarea
          bind:value={chatInput}
          on:keydown={handleChatKeydown}
          rows="3"
          placeholder="メッセージを入力... / Type a message..."
          disabled={chatLoading}
        ></textarea>
      </div>
      <div class="chat-buttons">
        <button on:click={handleSendChat} disabled={chatLoading || (!chatInput.trim() && !chatImageBase64)}>
          {chatLoading ? '送信中... / Sending...' : '送信 / Send'}
        </button>
        <button class="btn-secondary" on:click={clearChat} disabled={chatLoading}>
          クリア / Clear
        </button>
      </div>
    </div>
  </section>

  <hr class="divider" />

  <section class="split-section">
    <h2>Story Splitter / 原稿分割</h2>
    <p class="section-desc">原稿をページごとのプロンプトに分割します / Split manuscript into page prompts</p>

    <div class="split-form">
      <label>
        <span>Manuscript / 原稿</span>
        <textarea bind:value={ssManuscript} rows="8" placeholder="漫画の原稿やシナリオを入力..."></textarea>
      </label>
      <label>
        <span>System Prompt / 画風・世界観設定</span>
        <textarea bind:value={ssSystemPrompt} rows="4" placeholder="画風、キャラクター設定、世界観など..."></textarea>
      </label>
      <label>
        <span>Total Pages / ページ数</span>
        <input type="number" bind:value={ssTotalPages} min="1" max="20" />
      </label>

      <button on:click={handleSplitStory} disabled={ssLoading}>
        {ssLoading ? '分割中... / Splitting...' : '原稿を分割 / Split Story'}
      </button>
    </div>

    {#if ssError}
      <div class="error">{ssError}</div>
    {/if}

    {#if ssResult && ssResult.metadata}
      <div class="split-result">
        <h3>Result / 結果</h3>
        <div class="result-meta">
          <strong>Title:</strong> {ssResult.metadata?.title || '(no title)'} |
          <strong>Pages:</strong> {ssResult.metadata?.total_pages || '-'} |
          <strong>Style:</strong> {ssResult.metadata?.art_style || '-'}
        </div>

        <div class="result-pages">
          {#each ssResult.pages || [] as page}
            <div class="page-card">
              <h4>Page {page.page_number}</h4>
              <div class="page-fields">
                <div><strong>Reference Mode:</strong> {page.reference_mode}</div>
                <div><strong>Scene:</strong> {page.scene_time || '-'} @ {page.scene_location || '-'}</div>
                <div><strong>Mood:</strong> {page.mood || '-'}</div>
                <div><strong>Continuity:</strong> {page.continuity_note || '-'}</div>
                <div><strong>Layout:</strong> {page.layout_description || '-'}</div>
                <div class="page-prompt"><strong>Prompt:</strong> {page.full_page_prompt}</div>
                {#if page.speech_bubbles && page.speech_bubbles.length > 0}
                  <div class="page-bubbles">
                    <strong>Speech Bubbles:</strong>
                    {#each page.speech_bubbles as bubble}
                      <span class="bubble">「{bubble.text}」</span>
                    {/each}
                  </div>
                {/if}
              </div>
            </div>
          {/each}
        </div>

        <div class="raw-json-toggle">
          <button class="btn-secondary" on:click={() => ssShowRaw = !ssShowRaw}>
            {ssShowRaw ? 'Hide Raw JSON / JSONを隠す' : 'Show Raw JSON / JSONを表示'}
          </button>
        </div>

        {#if ssShowRaw}
          <pre class="raw-json">{ssRawJson}</pre>
        {/if}
      </div>
    {/if}
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

  .settings-panel {
    margin-bottom: 20px;
    padding: 16px;
    background: #f9f9f9;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
  }

  .settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
  }

  .settings-header h3 {
    margin: 0;
    font-size: 1rem;
    color: #333;
  }

  .btn-save-settings {
    padding: 8px 14px;
    background: #43a047;
    color: #fff;
    border: none;
    border-radius: 6px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: background 0.2s;
  }

  .btn-save-settings:hover {
    background: #388e3c;
  }

  .settings-fields {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .settings-fields label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.85rem;
    color: #555;
  }

  .settings-fields input {
    padding: 8px 10px;
    border: 1px solid #ccc;
    border-radius: 6px;
    font-size: 0.9rem;
    outline: none;
    transition: border-color 0.2s;
  }

  .settings-fields input:focus {
    border-color: #1976d2;
  }

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

  .chat-image {
    max-width: 200px;
    max-height: 200px;
    border-radius: 6px;
    margin-bottom: 6px;
    display: block;
  }

  .chat-image-preview {
    position: relative;
    display: inline-block;
  }

  .chat-image-preview img {
    max-width: 120px;
    max-height: 120px;
    border-radius: 6px;
    border: 1px solid #ccc;
  }

  .btn-remove-image {
    position: absolute;
    top: -8px;
    right: -8px;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: #c62828;
    color: #fff;
    border: none;
    font-size: 16px;
    line-height: 1;
    cursor: pointer;
    padding: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .btn-remove-image:hover {
    background: #b71c1c;
  }

  .chat-input-controls {
    display: flex;
    gap: 8px;
    align-items: flex-start;
  }

  .chat-input-controls textarea {
    flex: 1;
  }

  .btn-upload {
    display: inline-flex;
    align-items: center;
    padding: 10px 14px;
    background: #e0e0e0;
    color: #333;
    border-radius: 8px;
    font-size: 0.9rem;
    cursor: pointer;
    transition: background 0.2s;
    white-space: nowrap;
  }

  .btn-upload:hover {
    background: #bdbdbd;
  }

  .btn-upload input[type="file"] {
    display: none;
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

  /* ── Story Splitter styles ── */
  .split-section h2 {
    margin: 0 0 4px;
    font-size: 1.3rem;
    color: #222;
  }

  .split-form {
    display: flex;
    flex-direction: column;
    gap: 14px;
    margin-bottom: 16px;
  }

  .split-form input[type="number"] {
    width: 80px;
    padding: 8px 10px;
    border: 1px solid #ccc;
    border-radius: 6px;
    font-size: 1rem;
  }

  .split-result {
    margin-top: 16px;
    padding: 16px;
    background: #f9f9f9;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
  }

  .split-result h3 {
    margin: 0 0 12px;
    font-size: 1.1rem;
    color: #333;
  }

  .result-meta {
    margin-bottom: 16px;
    padding: 8px 12px;
    background: #e3f2fd;
    border-radius: 6px;
    font-size: 0.9rem;
    color: #444;
  }

  .result-pages {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .page-card {
    padding: 12px;
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
  }

  .page-card h4 {
    margin: 0 0 8px;
    font-size: 1rem;
    color: #1976d2;
  }

  .page-fields {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 0.9rem;
    color: #444;
  }

  .page-prompt {
    margin-top: 4px;
    padding: 8px;
    background: #fafafa;
    border-left: 3px solid #1976d2;
    font-family: monospace;
    font-size: 0.85rem;
    color: #333;
    line-height: 1.4;
  }

  .page-bubbles {
    margin-top: 4px;
  }

  .bubble {
    display: inline-block;
    margin: 2px 4px;
    padding: 2px 8px;
    background: #fff3e0;
    border-radius: 4px;
    font-size: 0.85rem;
  }

  .raw-json-toggle {
    margin-top: 16px;
    text-align: center;
  }

  .raw-json {
    margin-top: 12px;
    padding: 12px;
    background: #263238;
    color: #aed581;
    border-radius: 6px;
    font-size: 0.8rem;
    line-height: 1.4;
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 400px;
    overflow-y: auto;
  }
</style>
