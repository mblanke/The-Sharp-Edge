import { defineConfig } from 'vitest/config';

// Plain-TS unit tests (scaling mirror); no SvelteKit plugin needed.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts']
  }
});
