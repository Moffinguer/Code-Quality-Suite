// ESLint base for the quality suite. Lives in /opt/npm so plugin imports resolve there.
// why: optional plugins load lazily, so a JS-only image does not need the Vue/Svelte/Astro ones.
import js from "@eslint/js";
import globals from "globals";

const opt = async (name) => {
  try {
    return await import(name);
  } catch {
    return null;
  }
};

const tseslint = (await opt("typescript-eslint"))?.default;
const html = (await opt("eslint-plugin-html"))?.default;
const vue = (await opt("eslint-plugin-vue"))?.default;
const svelte = (await opt("eslint-plugin-svelte"))?.default;
const astro = (await opt("eslint-plugin-astro"))?.default;

const config = [
  { files: ["**/*.{js,mjs,cjs,jsx,ts,tsx,mts,cts,html,htm,xhtml,vue,svelte,astro}"], ...js.configs.recommended },
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.browser, ...globals.node },
    },
  },
];
if (tseslint) {
  config.push(
    ...tseslint.configs.recommended.map((c) => ({ files: ["**/*.{ts,tsx,mts,cts,vue,svelte,astro}"], ...c })),
  );
}
if (html) config.push({ files: ["**/*.{html,htm,xhtml}"], plugins: { html } });
if (vue) config.push(...vue.configs["flat/recommended"].map((c) => ({ files: ["**/*.vue"], ...c })));
if (svelte) config.push(...svelte.configs.recommended.map((c) => ({ files: ["**/*.svelte"], ...c })));
if (astro) config.push(...astro.configs.recommended.map((c) => ({ files: ["**/*.astro"], ...c })));

export default config;
