import { useState, useEffect } from "react";
import { Folder, FileCode2, ChevronRight, ChevronDown, Search, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { invoke } from "@tauri-apps/api/core";

interface FileNodeData {
  name: string;
  path: string;
  is_dir: boolean;
  children?: FileNodeData[];
}

function FileNode({ node, level = 0, workspacePath }: { node: FileNodeData; level?: number; workspacePath: string }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [children, setChildren] = useState<FileNodeData[] | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const { selectedFilePath, setSelectedFilePath } = useAgentsStore();

  const isSelected = selectedFilePath === node.path;

  const handleToggle = async () => {
    if (node.is_dir) {
      if (!isExpanded && !children) {
        try {
          setIsLoading(true);
          const absoluteDirPath = `${workspacePath}/${node.path}`;
          const result = await invoke<FileNodeData[]>("list_files", {
            workspacePath,
            directoryPath: absoluteDirPath
          });
          setChildren(result);
        } catch (error) {
          console.error("Failed to load directory:", error);
        } finally {
          setIsLoading(false);
        }
      }
      setIsExpanded(!isExpanded);
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
            ? "bg-purple-500/10 border-purple-500 text-white"
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
            <Folder className="h-3.5 w-3.5 text-zinc-500 shrink-0" />
          </>
        ) : (
          <>
            <div className="w-3.5" />
            <FileCode2 className="h-3.5 w-3.5 text-purple-400/50 shrink-0" />
          </>
        )}
        <span className="text-[12px] font-medium truncate">{node.name}</span>
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
  const [search, setSearch] = useState("");
  const [tree, setTree] = useState<FileNodeData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { repositoryGroups, selectedIssueId } = useAgentsStore();

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

  const filteredTree = tree.filter(node =>
    node.name.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="flex flex-col h-full bg-[#0A0A0A]">
      <div className="p-3 border-b border-white/[0.03]">
        <div className="relative group">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3 w-3 text-zinc-500 group-focus-within:text-purple-400 transition-colors" />
          <input
            type="text"
            placeholder="Filter files..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-zinc-900/50 border border-zinc-800 rounded-lg py-1.5 pl-8 pr-3 text-[11px] font-medium focus:outline-none focus:border-purple-500/50 transition-all placeholder:text-zinc-600"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto pt-2 custom-scrollbar">
        {isLoading ? (
          <div className="flex items-center justify-center h-full gap-2 text-zinc-500 text-[11px]">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Loading files...</span>
          </div>
        ) : filteredTree.length > 0 ? (
          filteredTree.map((node) => (
            <FileNode key={node.path} node={node} workspacePath={selectedIssue?.workspacePath || ""} />
          ))
        ) : (
          <div className="flex items-center justify-center h-full text-zinc-600 text-[11px]">
            No files found
          </div>
        )}
      </div>
    </div>
  );
}
