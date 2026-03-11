import * as React from "react";
import {
  CommandDialog,
  CommandEmpty,
  CommandInput,
  CommandList,
  CommandSeparator,
} from "@/components/ui/command";
import { AgentCommander } from "../commanders/agent-commander";
import { NavigationCommander } from "../commanders/navigation-commander";
import { SystemCommander } from "../commanders/system-commander";
import { ChevronLeft, Search } from "lucide-react";

export type CommandPage = "root" | "agents" | "skills" | "automations";

export function CommandPalette() {
  const [open, setOpen] = React.useState(false);
  const [page, setPage] = React.useState<CommandPage>("root");
  const [search, setSearch] = React.useState("");
  const inputRef = React.useRef<HTMLInputElement>(null);

  React.useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen((open) => !open);
      }

      if (e.key === "Backspace" && search === "" && page !== "root") {
        e.preventDefault();
        setPage("root");
      }
    };

    document.addEventListener("keydown", down);
    return () => document.removeEventListener("keydown", down);
  }, [page, search]);

  // Reset page when dialog opens/closes
  React.useEffect(() => {
    if (!open) {
      setPage("root");
      setSearch("");
    }
  }, [open]);

  const runCommand = (command: () => void) => {
    command();
    setOpen(false);
  };

  const handleSetPage = (newPage: CommandPage) => {
    setPage(newPage);
    setSearch("");
    // Focus after state change
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const getPlaceholder = () => {
    switch (page) {
      case "agents": return "Search threads or workspaces...";
      case "skills": return "Search and manage skills...";
      case "automations": return "Search and create automations...";
      default: return "Search files, threads, or commands...";
    }
  };

  return (
    <CommandDialog open={open} onOpenChange={setOpen}>
      <div className="flex flex-col">
        <div className="flex items-center px-4 py-3 relative border-b border-white/[0.03]">
          <div className="flex items-center justify-center w-5 h-5 mr-3 shrink-0">
            {page === "root" ? (
              <Search className="h-4 w-4 text-zinc-500" />
            ) : (
              <button
                onClick={() => handleSetPage("root")}
                className="group/back flex items-center justify-center -ml-1 h-7 w-7 rounded-lg hover:bg-white/5 text-zinc-400 hover:text-white transition-all active:scale-90"
              >
                <ChevronLeft className="h-4 w-4 group-hover:-translate-x-0.5 transition-transform" />
              </button>
            )}
          </div>

          <CommandInput
            ref={inputRef}
            placeholder={getPlaceholder()}
            value={search}
            onValueChange={setSearch}
            className="h-9"
          />

          {page !== "root" && search === "" && (
            <div className="absolute right-12 top-1/2 -translate-y-1/2 flex items-center gap-1.5 px-2 py-1 rounded-md bg-white/[0.03] border border-white/[0.05] pointer-events-none select-none animate-in fade-in zoom-in-95 duration-200">
              <span className="text-[9px] font-black text-zinc-500 uppercase tracking-[0.1em]">Backspace</span>
              <span className="text-[9px] font-medium text-zinc-600 uppercase tracking-wider">to back</span>
            </div>
          )}
        </div>

        <CommandList className="max-h-[450px] custom-scrollbar">
          <CommandEmpty>No results found.</CommandEmpty>

          <AgentCommander
            runCommand={runCommand}
            currentPage={page}
            setPage={handleSetPage}
          />

          {page === "root" && (
            <>
              <NavigationCommander runCommand={runCommand} />
              <CommandSeparator />
              <SystemCommander runCommand={runCommand} />
            </>
          )}
        </CommandList>
      </div>
    </CommandDialog>
  );
}
