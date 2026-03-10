import { useState } from "react";
import { Folder, FileCode2, ChevronRight, ChevronDown, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";

interface FileNode {
  name: string;
  type: "file" | "folder";
  children?: FileNode[];
  path: string;
}

const mockProjectTree: FileNode[] = [
  { name: ".agent", type: "folder", path: ".agent", children: [] },
  { name: ".agents", type: "folder", path: ".agents", children: [] },
  { name: ".ai", type: "folder", path: ".ai", children: [] },
  {
    name: "app",
    type: "folder",
    path: "app",
    children: [
      {
        name: "Actions",
        type: "folder",
        path: "app/Actions",
        children: [
          {
            name: "OnlineSale",
            type: "folder",
            path: "app/Actions/OnlineSale",
            children: [
              { name: "RequestTicketAccessAction.php", type: "file", path: "app/Actions/OnlineSale/RequestTicketAccessAction.php" },
              { name: "VerifyTicketAccessCodeAction.php", type: "file", path: "app/Actions/OnlineSale/VerifyTicketAccessCodeAction.php" },
            ],
          },
          { name: "Sisp", type: "folder", path: "app/Actions/Sisp", children: [] },
          { name: "Ticket", type: "folder", path: "app/Actions/Ticket", children: [] },
        ],
      },
      { name: "Models", type: "folder", path: "app/Models", children: [] },
      { name: "Http", type: "folder", path: "app/Http", children: [] },
    ],
  },
  { name: "config", type: "folder", path: "config", children: [] },
  { name: "database", type: "folder", path: "database", children: [] },
  { name: "routes", type: "folder", path: "routes", children: [] },
];

function FileNode({ node, level = 0 }: { node: FileNode; level?: number }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const { selectedFilePath, setSelectedFilePath } = useAgentsStore();

  const isSelected = selectedFilePath === node.path;

  const handleToggle = () => {
    if (node.type === "folder") {
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
        {node.type === "folder" ? (
          <>
            {isExpanded ? <ChevronDown className="h-3.5 w-3.5 shrink-0" /> : <ChevronRight className="h-3.5 w-3.5 shrink-0" />}
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

      {node.type === "folder" && isExpanded && node.children && (
        <div className="flex flex-col">
          {node.children.map((child) => (
            <FileNode key={child.path} node={child} level={level + 1} />
          ))}
        </div>
      )}
    </div>
  );
}

export function FileExplorer() {
  const [search, setSearch] = useState("");

  const filteredTree = mockProjectTree.filter(node =>
    node.name.toLowerCase().includes(search.toLowerCase()) ||
    (node.children && node.children.some(c => c.name.toLowerCase().includes(search.toLowerCase())))
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
        {filteredTree.map((node) => (
          <FileNode key={node.path} node={node} />
        ))}
      </div>
    </div>
  );
}
