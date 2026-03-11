import { useState, useEffect } from "react";
import { X, ExternalLink, Loader2 } from "lucide-react";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { invoke } from "@tauri-apps/api/core";

export function FileEditor() {
  const { selectedFilePath, setSelectedFilePath, repositoryGroups, selectedIssueId } = useAgentsStore();
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
      <div className="flex-1 overflow-auto p-6 font-mono text-[13px] leading-relaxed custom-scrollbar relative">
        {isLoading ? (
          <div className="absolute inset-0 flex items-center justify-center bg-[#0A0A0A]/80 backdrop-blur-sm z-10">
            <div className="flex items-center gap-2 text-zinc-500 text-[11px]">
              <Loader2 className="h-4 w-4 animate-spin text-purple-400" />
              <span>Reading file content...</span>
            </div>
          </div>
        ) : (
          <pre className="text-zinc-400">
            {content.split('\n').map((line, i) => (
              <div key={i} className="flex gap-6 group">
                <span className="w-8 text-right text-zinc-700 select-none group-hover:text-zinc-500 tabular-nums">{i + 1}</span>
                <span className={line.includes('class') || line.includes('function') || line.startsWith('<?php') ? 'text-zinc-200' : 'text-zinc-500'}>
                  {line || ' '}
                </span>
              </div>
            ))}
          </pre>
        )}
      </div>
    </div>
  );
}
