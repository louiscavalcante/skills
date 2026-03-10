# Project Type Detection

Reference protocol for detecting frontend project types. Used during Phase 0/Phase 2 to classify projects and determine test strategy.

---

## Detection Indicators

### Mobile

Any of the following in `package.json` or project root:

- `expo` in dependencies/devDependencies
- `react-native` in dependencies
- `@react-native-community/*` packages
- `app.json` with expo config (`expo` key)
- `eas.json` (Expo Application Services)
- `metro.config.js` or `metro.config.ts`

### Webapp

Any of the following in `package.json` or project root:

- `next` / `next.config.*` (Next.js)
- `react-dom` in dependencies
- `vercel.json` (Vercel deployment)
- `vite` / `vite.config.*` (Vite)
- `remix` / `remix.config.*` (Remix)
- `svelte` / `svelte.config.*` (SvelteKit)
- `nuxt` / `nuxt.config.*` (Nuxt)
- `angular` / `angular.json` (Angular)

### API-Only

No frontend indicators found in any scanned project. Backend services only.

---

## Scanning Process

1. Check `package.json` in the project root — scan `dependencies` and `devDependencies`
2. Check `relatedProjects[].path` — scan each related project's `package.json`
3. Check for framework config files in project root and related project roots

---

## Storage

- Main project: `project.frontendType` → `"mobile"` | `"webapp"` | `"api-only"`
- Related projects: `relatedProjects[].frontendType` → same values
- If both mobile and webapp indicators found → classify as `"webapp"` (browser testable takes priority for automation)

---

## Impact on Test Plan

| Frontend Type | E2E Strategy | Browser Tools | Guided Mode |
|---------------|-------------|---------------|-------------|
| `mobile` | Guided steps for physical device | Not loaded | `guided/mobile` — user performs actions on device |
| `webapp` | `agent-browser` / Playwright | Loaded in autonomous mode | `guided/webapp` — user performs actions in browser |
| `api-only` | Integration tests only (curl) | Not loaded | Not applicable — no UI to guide |
