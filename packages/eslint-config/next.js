// @ts-check
const { default: nextPlugin } = require("@next/eslint-plugin-next");
const baseConfig = require("./index");
const tseslint = require("typescript-eslint");

/**
 * ESLint config for Next.js apps.
 * Extends the base config with Next.js-specific rules.
 * @type {import("typescript-eslint").Config}
 */
const nextConfig = tseslint.config(...baseConfig, {
  plugins: {
    "@next/next": nextPlugin,
  },
  rules: {
    ...nextPlugin.configs.recommended.rules,
    ...nextPlugin.configs["core-web-vitals"].rules,
  },
});

module.exports = nextConfig;
