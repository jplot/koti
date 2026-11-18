# koti front

The koti web interface: sign-in, then the home plan in 2D (SVG) or 3D (Three.js). Built with Vue 3, TypeScript, Vite and shadcn-vue on Tailwind 4, on Node 26.

## Develop

```sh
cd front
npm ci
npm run dev
```

`npm run dev` serves the front on http://localhost:5173 and forwards `/api` to the Rails app on port 3000 (`cd app && bin/rails server`).

```sh
npm run check
```

`npm run check` runs oxlint, ESLint, vue-tsc and Vitest with coverage: 95 % of lines overall and 70 % per file. It must pass before every commit.

`src/components/ui` holds shadcn-vue components, which `npx shadcn-vue@latest add <name>` copies in; they stay out of linting and coverage.
