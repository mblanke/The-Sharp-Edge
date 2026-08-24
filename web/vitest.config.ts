import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Plain-TS unit tests (scaling mirror, proxy handler); no SvelteKit plugin needed.
export default defineConfig({
  resolve: {
    alias: {
      '$env/dynamic/private': fileURLToPath(new URL('./src/test/env-stub.ts', import.meta.url))
    }
  },
  test: {
    include: ['src/**/*.test.ts']
  }
});
