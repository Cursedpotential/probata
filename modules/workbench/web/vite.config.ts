// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import { fileURLToPath, URL } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    outDir: "dist",
    sourcemap: true,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      // The integration API carries the new Proffer/Review contracts and uses
      // fixed, non-secret actor headers only on the localhost development hop.
      "/api/proffer": {
        target: "http://127.0.0.1:8021",
        headers: {
          "X-authentik-uid": "local-codex-preview",
          "X-authentik-username": "local-codex-preview",
        },
      },
      // Existing Workbench surfaces continue to use the deployed API so the
      // whole portal remains populated while the integration API is reviewed.
      "/api": {
        target: "https://workbench.tilapia-skilift.ts.net",
        changeOrigin: true,
      },
      "/health": "http://127.0.0.1:8021",
    },
  },
});
