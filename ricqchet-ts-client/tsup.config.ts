import { defineConfig } from "tsup";

export default defineConfig({
  entry: {
    index: "src/index.ts",
    realtime: "src/realtime/index.ts",
    react: "src/react/index.ts",
    next: "src/next/index.ts",
  },
  format: ["cjs", "esm"],
  dts: true,
  clean: true,
  sourcemap: true,
  // `phoenix` and `react` are optional peer dependencies — never bundle them.
  external: ["phoenix", "react"],
  // esbuild natively preserves the `"use client"` directive from
  // src/react/index.ts in both the ESM (line 1) and CJS outputs, so RSC
  // bundlers treat the react entry as a client boundary.
});
