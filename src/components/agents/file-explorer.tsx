import { useState, useEffect } from "react";
import { Folder, FileCode2, ChevronRight, ChevronDown, Search, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { invoke } from "@tauri-apps/api/core";
import { useI18n } from "@/i18n/i18n";

interface FileNodeData {
  name: string;
  path: string;
  is_dir: boolean;
  children?: FileNodeData[];
}

function FileNode({ node, level = 0, workspacePath }: { node: FileNodeData; level?: number; workspacePath: string }) {
  const { isFilesAllExpanded, selectedFilePath, setSelectedFilePath } = useAgentsStore();
  const [isExpanded, setIsExpanded] = useState(false);
  const [children, setChildren] = useState<FileNodeData[] | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (node.is_dir) {
      if (isFilesAllExpanded && !isExpanded) {
        if (!children) {
          loadDir();
        } else {
          setIsExpanded(true);
        }
      } else if (!isFilesAllExpanded && isExpanded) {
        setIsExpanded(false);
      }
    }
  }, [isFilesAllExpanded]);

  const loadDir = async () => {
    try {
      setIsLoading(true);
      const absoluteDirPath = `${workspacePath}/${node.path}`;
      const result = await invoke<FileNodeData[]>("list_files", {
        workspacePath,
        directoryPath: absoluteDirPath
      });
      setChildren(result);
      setIsExpanded(true);
    } catch (error) {
      console.error("Failed to load directory:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const isSelected = selectedFilePath === node.path;

  const handleToggle = async () => {
    if (node.is_dir) {
      if (!isExpanded && !children) {
        await loadDir();
      } else {
        setIsExpanded(!isExpanded);
      }
    } else {
      setSelectedFilePath(node.path);
    }
  };
  return (
    <div className="flex flex-col">
      <div
        onClick={handleToggle}
        className={cn(
          "flex items-center gap-2 py-1 px-2 cursor-pointer transition-colors border-l-2",
          isSelected
            ? "bg-purple-500/10 border-purple-500 text-white font-medium"
            : "border-transparent hover:bg-white/5 text-zinc-400 hover:text-zinc-200"
        )}
        style={{ paddingLeft: `${level * 16 + 8}px` }}
      >
        {node.is_dir ? (
          <>
            {isLoading ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin shrink-0 text-purple-400" />
            ) : (
              isExpanded ? <ChevronDown className="h-3.5 w-3.5 shrink-0" /> : <ChevronRight className="h-3.5 w-3.5 shrink-0" />
            )}
            <Folder className={cn("h-3.5 w-3.5 shrink-0", isExpanded ? "text-purple-400/80" : "text-zinc-600")} />
          </>
        ) : (
          <>
            <div className="w-3.5" />
            <FileCode2 className="h-3.5 w-3.5 text-purple-400/50 shrink-0" />
          </>
        )}
        <span className="text-[12px] truncate">{node.name}</span>
      </div>

      {node.is_dir && isExpanded && children && (
        <div className="flex flex-col">
          {children.map((child) => (
            <FileNode key={child.path} node={child} level={level + 1} workspacePath={workspacePath} />
          ))}
        </div>
      )}
    </div>
  );
}

export function FileExplorer() {
  const { t } = useI18n();
  const [search, setSearch] = useState("");
  const [tree, setTree] = useState<FileNodeData[]>([]);
  const [searchResults, setSearchResults] = useState<FileNodeData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSearching, setIsSearching] = useState(false);
  const { repositoryGroups, selectedIssueId, setSelectedFilePath, selectedFilePath } = useAgentsStore();

  const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
  const selectedIssue = allIssues.find((i) => i.id === selectedIssueId);

  useEffect(() => {
    async function loadFiles() {
      if (!selectedIssue?.workspacePath) {
        setTree([]);
        setIsLoading(false);
        return;
      }

      try {
        setIsLoading(true);
        const result = await invoke<FileNodeData[]>("list_files", {
          workspacePath: selectedIssue.workspacePath,
          directoryPath: selectedIssue.workspacePath
        });
        setTree(result);
      } catch (error) {
        console.error("Failed to load workspace files:", error);
      } finally {
        setIsLoading(false);
      }
    }

    loadFiles();
  }, [selectedIssue?.workspacePath]);

  // Handle Search
  useEffect(() => {
    const timer = setTimeout(async () => {
      if (!search.trim() || !selectedIssue?.workspacePath) {
        setSearchResults([]);
        setIsSearching(false);
        return;
      }

      try {
        setIsSearching(true);
        const result = await invoke<FileNodeData[]>("search_files", {
          workspacePath: selectedIssue.workspacePath,
          query: search
        });
        setSearchResults(result);
      } catch (error) {
        console.error("Search failed:", error);
      } finally {
        setIsSearching(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [search, selectedIssue?.workspacePath]);

  return (
    <div className="flex flex-col h-full bg-background">
      <div className="px-4 py-3 border-b border-white/[0.03]">
        <div className="relative group">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-600 group-focus-within:text-purple-500/50 transition-colors" />
          <input
            type="text"
            placeholder={t("agents.fileExplorer.searchPlaceholder")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-white/[0.03] border border-white/[0.05] rounded-md py-1.5 pl-9 pr-8 text-[11px] text-zinc-200 focus:outline-none focus:border-purple-500/30 focus:bg-white/[0.05] transition-all placeholder:text-zinc-600 font-medium"
          />
          {isSearching && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2">
              <Loader2 className="h-3 w-3 animate-spin text-purple-500/40" />
            </div>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto pt-2 custom-scrollbar">
        {isLoading ? (
          <div className="flex items-center justify-center h-full gap-2 text-zinc-500 text-[11px]">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>{t("agents.fileExplorer.loading")}</span>
          </div>
        ) : search.trim() ? (
          searchResults.length > 0 ? (
            <div className="flex flex-col">
              <div className="px-3 py-1 mb-2">
                <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-600">{t("agents.fileExplorer.results").replace("{count}", String(searchResults.length))}</span>
              </div>
              {searchResults.map((node) => (
                <div
                  key={node.path}
                  onClick={() => setSelectedFilePath(node.path)}
                  className={cn(
                    "flex flex-col px-4 py-2 cursor-pointer border-l-2 transition-all",
                    selectedFilePath === node.path
                      ? "bg-purple-500/10 border-purple-500"
                      : "border-transparent hover:bg-white/5"
                  )}
                >
                  <div className="flex items-center gap-2">
                    <FileCode2 className="h-3.5 w-3.5 text-purple-400/50" />
                    <span className={cn(
                      "text-[12px] font-medium",
                      selectedFilePath === node.path ? "text-white" : "text-zinc-300"
                    )}>{node.name}</span>
                  </div>
                  <span className="text-[10px] text-zinc-600 font-mono truncate">{node.path}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center h-full gap-4 px-6 text-center">
              <div className="h-10 w-10 rounded-full bg-zinc-900 flex items-center justify-center border border-white/5">
                <Search className="h-4 w-4 text-zinc-700" />
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[11px] text-zinc-400 font-medium">{t("agents.fileExplorer.noResults").replace("{query}", search)}</span>
                <span className="text-[10px] text-zinc-600 uppercase tracking-widest font-bold">{t("agents.fileExplorer.tryDifferent")}</span>
              </div>
            </div>
          )
        ) : tree.length > 0 ? (
          tree.map((node) => (
            <FileNode key={node.path} node={node} workspacePath={selectedIssue?.workspacePath || ""} />
          ))
        ) : (
          <div className="flex items-center justify-center h-full text-zinc-600 text-[11px]">
            {t("agents.fileExplorer.noFiles")}
          </div>
        )}
      </div>
    </div>
  );
}

