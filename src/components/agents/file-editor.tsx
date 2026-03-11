import { useState, useEffect } from "react";
import { X, ExternalLink, Loader2 } from "lucide-react";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useSettingsStore } from "@/stores/settings-store";
import { invoke } from "@tauri-apps/api/core";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark
} from "react-syntax-highlighter/dist/esm/styles/prism";

const THEMES: Record<string, any> = {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
};

export function FileEditor() {
  const { selectedFilePath, setSelectedFilePath, repositoryGroups, selectedIssueId } = useAgentsStore();
  const { editorTheme } = useSettingsStore();
  const [content, setContent] = useState<string>("");
  const [isLoading, setIsLoading] = useState(false);

  const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
  const selectedIssue = allIssues.find((i) => i.id === selectedIssueId);

  useEffect(() => {
    async function loadFileContent() {
      if (!selectedFilePath || !selectedIssue?.workspacePath) {
        setContent("");
        return;
      }

      try {
        setIsLoading(true);
        const absolutePath = `${selectedIssue.workspacePath}/${selectedFilePath}`;
        const result = await invoke<string>("read_file", { path: absolutePath });
        setContent(result);
      } catch (error) {
        console.error("Failed to read file:", error);
        setContent(`Error loading file: ${error}`);
      } finally {
        setIsLoading(false);
      }
    }

    loadFileContent();
  }, [selectedFilePath, selectedIssue?.workspacePath]);

  if (!selectedFilePath) return null;

  const getLanguage = (filename: string) => {
    const ext = filename.split('.').pop()?.toLowerCase();
    const map: Record<string, string> = {
      'js': 'javascript',
      'ts': 'typescript',
      'tsx': 'tsx',
      'jsx': 'jsx',
      'php': 'php',
      'rs': 'rust',
      'py': 'python',
      'sql': 'sql',
      'json': 'json',
      'md': 'markdown',
      'html': 'html',
      'css': 'css',
      'yml': 'yaml',
      'yaml': 'yaml',
    };
    return map[ext || ''] || 'text';
  };

  return (
    <div className="flex flex-col h-full bg-[#0A0A0A] border-r border-white/[0.03]">
      {/* Editor Header */}
      <div className="h-10 border-b border-white/[0.03] flex items-center justify-between px-4 bg-[#0D0D0D]">
        <div className="flex items-center gap-2 overflow-hidden">
          <span className="text-[10px] text-zinc-500 font-mono truncate">{selectedFilePath}</span>
          <button className="p-1 hover:bg-white/5 rounded text-zinc-500">
            <ExternalLink className="h-3 w-3" />
          </button>
        </div>
        <button
          onClick={() => setSelectedFilePath(null)}
          className="p-1 hover:bg-red-500/10 hover:text-red-500 rounded text-zinc-500 transition-colors"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Editor Content */}
      <div className="flex-1 overflow-hidden relative group">
        {isLoading && (
          <div className="absolute inset-0 flex items-center justify-center bg-[#0A0A0A]/80 backdrop-blur-sm z-10">
            <div className="flex items-center gap-2 text-zinc-500 text-[11px]">
              <Loader2 className="h-4 w-4 animate-spin text-purple-400" />
              <span>Reading file content...</span>
            </div>
          </div>
        )}

        <div className="h-full w-full overflow-auto custom-scrollbar pt-2 pb-6">
          <SyntaxHighlighter
            language={getLanguage(selectedFilePath)}
            style={THEMES[editorTheme] || oneDark}
            showLineNumbers={true}
            lineNumberStyle={{ minWidth: '3.5em', paddingRight: '2em', color: '#333', textAlign: 'right', fontSize: '11px', userSelect: 'none' }}
            codeTagProps={{
              style: {
                background: 'none',
              }
            }}
            customStyle={{
              margin: 0,
              padding: '1.5rem 0',
              background: 'transparent',
              fontSize: '13px',
              fontFamily: 'JetBrains Mono, Menlo, Monaco, Consolas, "Courier New", monospace',
              lineHeight: '1.6',
            }}
          >
            {content || ' '}
          </SyntaxHighlighter>
        </div>
      </div>
    </div>
  );
}
