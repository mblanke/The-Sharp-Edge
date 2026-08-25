import { defineConfig, devices } from '@playwright/test';

// Full-stack e2e: sqlite-seeded FastAPI (api/scripts/e2e_server.py) + built web app.
export default defineConfig({
  testDir: 'e2e',
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure'
  },
  projects: [
    { name: 'iphone', use: { ...devices['iPhone 13'] } },
    { name: 'ipad', use: { ...devices['iPad (gen 7) landscape'] } }
  ],
  webServer: [
    {
      command: 'uv run --extra dev python scripts/e2e_server.py',
      cwd: '../api',
      url: 'http://127.0.0.1:8001/api/v1/healthz',
      reuseExistingServer: !process.env.CI,
      timeout: 60_000
    },
    {
      command: 'npm run build && npm run preview -- --port 4173 --strictPort',
      url: 'http://127.0.0.1:4173',
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      env: { API_URL: 'http://127.0.0.1:8001', API_TOKEN: 'e2e-token' }
    }
  ]
});
