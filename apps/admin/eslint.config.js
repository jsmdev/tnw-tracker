const baseConfig = require("@tnw/eslint-config");

module.exports = [
  ...baseConfig,
  {
    ignores: [".next/**", "next-env.d.ts", "eslint.config.js"],
  },
];
