import {
  PanelLeft,
  Settings
} from "lucide-react";
import { CommandGroup, CommandItem, CommandShortcut } from "@/components/ui/command";
import { useSettingsStore } from "@/stores/settings-store";
import { useNavigationStore } from "@/stores/navigation-store";

interface SystemCommanderProps {
  runCommand: (command: () => void) => void;
}

export function SystemCommander({ runCommand }: SystemCommanderProps) {
  const { sidebarOpen, setSidebarOpen } = useSettingsStore();
  const { navigateTo } = useNavigationStore();

  return (
    <CommandGroup heading="System Actions">
      <CommandItem onSelect={() => runCommand(() => setSidebarOpen(!sidebarOpen))}>
        <PanelLeft className="mr-2 h-4 w-4 text-zinc-400" />
        <span>Toggle Sidebar</span>
        <CommandShortcut>⌘B</CommandShortcut>
      </CommandItem>
      <CommandItem onSelect={() => runCommand(() => navigateTo("settings"))}>
        <Settings className="mr-2 h-4 w-4 text-zinc-400" />
        <span>Settings</span>
        <CommandShortcut>⌘S</CommandShortcut>
      </CommandItem>
    </CommandGroup>
  );
}
