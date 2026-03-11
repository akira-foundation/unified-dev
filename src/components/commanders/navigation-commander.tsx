import {
  LayoutDashboard,
  Bot,
  FolderGit2
} from "lucide-react";
import { CommandGroup, CommandItem, CommandShortcut } from "@/components/ui/command";
import { useNavigationStore } from "@/stores/navigation-store";

interface NavigationCommanderProps {
  runCommand: (command: () => void) => void;
}

export function NavigationCommander({ runCommand }: NavigationCommanderProps) {
  const { navigateTo } = useNavigationStore();

  return (
    <CommandGroup heading="Navigation">
      <CommandItem onSelect={() => runCommand(() => navigateTo("dashboard"))}>
        <LayoutDashboard className="mr-2 h-4 w-4 text-zinc-400" />
        <span>Dashboard</span>
        <CommandShortcut>⌘D</CommandShortcut>
      </CommandItem>
      <CommandItem onSelect={() => runCommand(() => navigateTo("agents"))}>
        <Bot className="mr-2 h-4 w-4 text-zinc-400" />
        <span>Agents</span>
        <CommandShortcut>⌘A</CommandShortcut>
      </CommandItem>
      <CommandItem onSelect={() => runCommand(() => navigateTo("repository"))}>
        <FolderGit2 className="mr-2 h-4 w-4 text-zinc-400" />
        <span>Repositories</span>
        <CommandShortcut>⌘R</CommandShortcut>
      </CommandItem>
    </CommandGroup>
  );
}
