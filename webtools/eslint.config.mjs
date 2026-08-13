import js from "@eslint/js";
import tseslint from "typescript-eslint";
import html from "eslint-plugin-html";
import globals from "globals";

export default [
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.html", "**/*.htm", "**/*.xhtml"],
    plugins: { html },
  },
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.browser, ...globals.node },
    },
  },
];
