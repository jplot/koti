import { fileURLToPath } from 'node:url'
import { mergeConfig, defineConfig, configDefaults } from 'vitest/config'
import viteConfig from './vite.config.ts'

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      environment: 'jsdom',
      exclude: [...configDefaults.exclude, 'e2e/**'],
      root: fileURLToPath(new URL('./', import.meta.url)),
      coverage: {
        provider: 'v8',
        include: ['src/**/*.{ts,vue}'],
        // Copied in by the shadcn-vue CLI, not written here; main.ts only mounts the app.
        exclude: ['src/components/ui/**', 'src/main.ts', 'src/**/__tests__/**'],
        reporter: ['text', 'json-summary'],
        thresholds: { lines: 95 },
      },
    },
  }),
)
