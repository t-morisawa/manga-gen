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
 * @param {{ message: string, google_api_key: string, api_base_url: string, model_name: string, history: Array<{ role: string, text: string }> }} request
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
