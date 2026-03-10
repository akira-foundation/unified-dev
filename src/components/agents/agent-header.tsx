import { Badge } from "@/components/ui/badge";
import type { AgentIssue } from "@/types/agents";
import { cn } from "@/lib/utils";
import {
  ChevronDown,
  GitPullRequest,
  Monitor,
  CloudUpload
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";

interface AgentHeaderProps {
  issue: AgentIssue;
}

export function AgentHeader({ issue }: AgentHeaderProps) {
  return (
    <header className="h-14 border-b border-white/[0.03] flex items-center px-6 bg-[#0A0A0A] backdrop-blur-md justify-between shrink-0">
      {/* Title & Metadata (Left Aligned) */}
      <div className="flex flex-col gap-0.5 min-w-0">
        <div className="flex items-center gap-3">
          <h1 className="text-[14px] font-semibold tracking-tight text-white/90 truncate max-w-xl">
            {issue.title}
          </h1>
          <Badge
            variant="outline"
            className={cn(
              "text-[9px] font-medium px-2 py-0 h-4 min-h-0 border-none transition-all",
              issue.status === "Running" ? "bg-blue-500/10 text-blue-400" :
                issue.status === "Completed" ? "bg-emerald-500/10 text-emerald-400" :
                  "bg-zinc-800 text-zinc-400"
            )}
          >
            {issue.status}
          </Badge>
        </div>
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground/40 font-medium">
          <span className="hover:text-zinc-400 transition-colors cursor-default">{issue.repoName}</span>
          <span className="text-zinc-800">/</span>
          <span className="font-mono text-[10px] hover:text-zinc-400 transition-colors cursor-default">{issue.branchName}</span>
        </div>
      </div>

      {/* Actions (Right Aligned Menu) */}
      <div className="flex items-center gap-3">
        {issue.status === "Running" ? (
          <Button
            variant="ghost"
            className="h-8 rounded-xl px-4 text-[11px] font-bold uppercase tracking-widest bg-red-500/5 text-red-500/70 hover:bg-red-500/10 border border-red-500/10"
          >
            Stop Agent
          </Button>
        ) : (
          <div className="flex items-center">
            {/* Split Action Button - Match Dropdown Aesthetic */}
            <div className="flex items-center bg-[#0F0F0F] rounded-xl border border-white/5 shadow-2xl overflow-hidden transition-all duration-300">
              <Button
                variant="ghost"
                className="h-8 pl-4 pr-3 text-white/90 text-[12px] font-semibold gap-2.5 rounded-none hover:bg-transparent cursor-default border-none"
              >
                <GitPullRequest className="h-4 w-4 text-[#A855F7]" />
                <span>Draft PR</span>
              </Button>

              <div className="w-[1px] h-3.5 bg-white/10" />

              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-9 rounded-none hover:bg-white/5 text-zinc-400 hover:text-white transition-colors border-none"
                  >
                    <ChevronDown className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  align="end"
                  className="w-80 bg-[#0F0F0F] border-white/[0.05] p-2 shadow-2xl rounded-2xl backdrop-blur-3xl animate-in fade-in zoom-in-95 duration-200"
                >
                  <DropdownMenuItem className="flex items-start gap-3.5 p-3.5 focus:bg-white/[0.03] rounded-xl cursor-pointer group transition-all duration-200">
                    <div className="h-9 w-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0 border border-white/5 group-hover:bg-[#A855F7]/10 group-hover:border-[#A855F7]/20 transition-all duration-200">
                      <Monitor className="h-4 w-4 text-zinc-400 group-hover:text-[#A855F7]" />
                    </div>
                    <div className="flex flex-col gap-0.5">
                      <span className="text-[13px] font-semibold text-white/90 tracking-tight">Merge locally</span>
                      <span className="text-[11px] text-zinc-500 leading-tight">Sync changes with your local base branch</span>
                    </div>
                  </DropdownMenuItem>

                  <DropdownMenuItem className="flex items-start gap-3.5 p-3.5 focus:bg-white/[0.03] rounded-xl cursor-pointer group transition-all duration-200">
                    <div className="h-9 w-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0 border border-white/5 group-hover:bg-[#A855F7]/10 group-hover:border-[#A855F7]/20 transition-all duration-200">
                      <CloudUpload className="h-4 w-4 text-zinc-400 group-hover:text-[#A855F7]" />
                    </div>
                    <div className="flex flex-col gap-0.5">
                      <span className="text-[13px] font-semibold text-white/90 tracking-tight">Merge and push</span>
                      <span className="text-[11px] text-zinc-500 leading-tight">Update local and sync with remote repository</span>
                    </div>
                  </DropdownMenuItem>

                  <DropdownMenuSeparator className="bg-white/[0.03] my-2" />

                  <DropdownMenuItem className="flex items-start gap-3.5 p-3.5 focus:bg-white/[0.03] rounded-xl cursor-pointer group transition-all duration-200">
                    <div className="h-9 w-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0 border border-white/5 group-hover:bg-[#A855F7]/10 group-hover:border-[#A855F7]/20 transition-all duration-200">
                      <GitPullRequest className="h-4 w-4 text-zinc-400 group-hover:text-[#A855F7]" />
                    </div>
                    <div className="flex flex-col gap-0.5">
                      <span className="text-[13px] font-semibold text-white/90 tracking-tight">Create pull request</span>
                      <span className="text-[11px] text-zinc-500 leading-tight">Initialize a new PR directly on GitHub</span>
                    </div>
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        )}
      </div>
    </header>
  );
}
