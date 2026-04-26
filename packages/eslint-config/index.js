// @ts-check
const js = require("@eslint/js");
const tseslint = require("typescript-eslint");

/**
 * Base ESLint config for all TypeScript packages.
 * @type {import("typescript-eslint").Config}
 */
const baseConfig = tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports", fixStyle: "inline-type-imports" },
      ],
    },
  }
);

module.exports = baseConfig;
