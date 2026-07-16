import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:5003',
        timeout: 300000,
        proxyTimeout: 300000,
      },
      '/backend': {
        target: 'http://localhost:5003',
        timeout: 300000,
        proxyTimeout: 300000,
      },
    },
  },
})
