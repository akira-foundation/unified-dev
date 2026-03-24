import hljs from "highlight.js/lib/core";

// Register only commonly used languages to keep bundle size small
import typescript from "highlight.js/lib/languages/typescript";
import javascript from "highlight.js/lib/languages/javascript";
import xml from "highlight.js/lib/languages/xml";
import css from "highlight.js/lib/languages/css";
import json from "highlight.js/lib/languages/json";
import yaml from "highlight.js/lib/languages/yaml";
import bash from "highlight.js/lib/languages/bash";
import php from "highlight.js/lib/languages/php";
import rust from "highlight.js/lib/languages/rust";
import python from "highlight.js/lib/languages/python";
import go from "highlight.js/lib/languages/go";
import ruby from "highlight.js/lib/languages/ruby";
import sql from "highlight.js/lib/languages/sql";
import markdown from "highlight.js/lib/languages/markdown";
import dockerfile from "highlight.js/lib/languages/dockerfile";
import ini from "highlight.js/lib/languages/ini";
import java from "highlight.js/lib/languages/java";
import csharp from "highlight.js/lib/languages/csharp";
import cpp from "highlight.js/lib/languages/cpp";
import swift from "highlight.js/lib/languages/swift";
import kotlin from "highlight.js/lib/languages/kotlin";

hljs.registerLanguage("typescript", typescript);
hljs.registerLanguage("javascript", javascript);
hljs.registerLanguage("xml", xml);
hljs.registerLanguage("css", css);
hljs.registerLanguage("json", json);
hljs.registerLanguage("yaml", yaml);
hljs.registerLanguage("bash", bash);
hljs.registerLanguage("php", php);
hljs.registerLanguage("rust", rust);
hljs.registerLanguage("python", python);
hljs.registerLanguage("go", go);
hljs.registerLanguage("ruby", ruby);
hljs.registerLanguage("sql", sql);
hljs.registerLanguage("markdown", markdown);
hljs.registerLanguage("dockerfile", dockerfile);
hljs.registerLanguage("ini", ini);
hljs.registerLanguage("java", java);
hljs.registerLanguage("csharp", csharp);
hljs.registerLanguage("cpp", cpp);
hljs.registerLanguage("swift", swift);
hljs.registerLanguage("kotlin", kotlin);

const EXT_MAP: Record<string, string> = {
  ts: "typescript",
  tsx: "typescript",
  js: "javascript",
  jsx: "javascript",
  mjs: "javascript",
  cjs: "javascript",
  html: "xml",
  htm: "xml",
  vue: "xml",
  svg: "xml",
  css: "css",
  scss: "css",
  less: "css",
  json: "json",
  jsonc: "json",
  yaml: "yaml",
  yml: "yaml",
  sh: "bash",
  bash: "bash",
  zsh: "bash",
  php: "php",
  rs: "rust",
  py: "python",
  go: "go",
  rb: "ruby",
  sql: "sql",
  md: "markdown",
  mdx: "markdown",
  dockerfile: "dockerfile",
  toml: "ini",
  ini: "ini",
  env: "ini",
  java: "java",
  cs: "csharp",
  cpp: "cpp",
  cc: "cpp",
  cxx: "cpp",
  c: "cpp",
  h: "cpp",
  swift: "swift",
  kt: "kotlin",
  kts: "kotlin",
};

export function getLanguageFromFilename(filename: string): string | null {
  const base = filename.split("/").pop() ?? filename;
  if (base.toLowerCase() === "dockerfile") return "dockerfile";
  const ext = base.split(".").pop()?.toLowerCase();
  if (!ext) return null;
  return EXT_MAP[ext] ?? null;
}

export function highlightLine(code: string, language: string): string {
  try {
    return hljs.highlight(code, { language, ignoreIllegals: true }).value;
  } catch {
    return escapeHtml(code);
  }
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
