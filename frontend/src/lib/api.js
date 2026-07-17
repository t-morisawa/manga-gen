const API_BASE = '';

/**
 * @param {{ prompt: string, google_api_key: string }} request
 * @returns {Promise<{ success: boolean, image_url?: string, error?: string }>}
 */
export async function generateImage(request) {
  const res = await fetch(`${API_BASE}/api/generate-image`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  return await res.json();
}

/**
 * @param {{ message: string, google_api_key: string, api_base_url: string, model_name: string, image?: string, history: Array<{ role: string, text: string, image?: string }> }} request
 * @returns {Promise<{ success: boolean, reply?: string, error?: string }>}
 */
export async function chat(request) {
  const res = await fetch(`${API_BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  return await res.json();
}

export async function healthCheck() {
  const res = await fetch(`${API_BASE}/api/health`);
  return await res.json();
}

export async function getSettings() {
  const res = await fetch(`${API_BASE}/api/settings`);
  return await res.json();
}

export async function saveSettings(settings) {
  const res = await fetch(`${API_BASE}/api/settings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(settings),
  });
  return await res.json();
}

/**
 * @param {{ manuscript: string, system_prompt: string, total_pages: number, api_key: string, api_base_url: string, model_name: string }} request
 * @returns {Promise<{ success: boolean, data?: object, raw_json?: string, error?: string }>}
 */
export async function splitStory(request) {
  const controller = new AbortController();
  // Abort after 5 minutes (300s) to prevent indefinite hanging
  const timeoutId = setTimeout(() => controller.abort(), 300000);
  try {
    const res = await fetch(`${API_BASE}/api/split-story`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`HTTP ${res.status}: ${errText}`);
    }
    return await res.json();
  } catch (e) {
    clearTimeout(timeoutId);
    if (e.name === 'AbortError') {
      throw new Error('Request timed out after 5 minutes');
    }
    throw e;
  }
}

/**
 * @param {{ manuscript: string, system_prompt: string, total_pages: number, api_key: string, api_base_url: string, model_name: string, google_api_key: string, style_image?: string | null }} request
 * @returns {Promise<{ success: boolean, job_id?: string, error?: string }>}
 */
export async function generatePages(request) {
  const res = await fetch(`${API_BASE}/api/generate-pages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  return await res.json();
}

/**
 * @param {string} jobId
 * @returns {Promise<{ job_id: string, status: string, title?: string, total_pages: number, pages: Array<{ page_number: number, status: string, image_url?: string, prompt: string, error?: string }> }>}
 */
export async function getJobStatus(jobId) {
  const res = await fetch(`${API_BASE}/api/jobs/${jobId}`);
  return await res.json();
}
