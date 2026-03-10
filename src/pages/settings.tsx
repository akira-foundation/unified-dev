import { useState } from "react";
import {
  Settings2,
  Palette,
  SlidersHorizontal,
  Bell,
  Blocks,
  Bot,
  Keyboard,
  Mic,
  Wrench,
  LogOut,
  Minus,
  Plus,
  Unplug,
  Link2,
  Github,
  FolderGit2,
  FileText
} from "lucide-react";
import { cn } from "@/lib/utils";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

const TABS = [
  { id: "general", label: "General", icon: <Settings2 className="h-4 w-4" /> },
  { id: "appearance", label: "Appearance", icon: <Palette className="h-4 w-4" /> },
  { id: "behaviour", label: "Behaviour", icon: <SlidersHorizontal className="h-4 w-4" /> },
  { id: "notifications", label: "Notifications", icon: <Bell className="h-4 w-4" /> },
  { id: "integrations", label: "Integrations", icon: <Blocks className="h-4 w-4" /> },
  { id: "agents", label: "Coding Agents", icon: <Bot className="h-4 w-4" /> },
  { id: "shortcuts", label: "Shortcuts", icon: <Keyboard className="h-4 w-4" /> },
  { id: "dictation", label: "Dictation", icon: <Mic className="h-4 w-4" /> },
  { id: "advanced", label: "Advanced", icon: <Wrench className="h-4 w-4" /> },
  { id: "github", label: "GitHub", icon: <Github className="h-4 w-4" /> },
  { id: "workspaces", label: "Workspaces", icon: <FolderGit2 className="h-4 w-4" /> },
  { id: "prompts", label: "Prompts", icon: <FileText className="h-4 w-4" /> },
];

export function SettingsPage() {
  const [activeTab, setActiveTab] = useState("general");

  return (
    <div className="flex h-screen bg-[#1c1c1c] text-zinc-300">
      {/* Sidebar Navigation */}
      <div className="w-64 border-r border-white/5 bg-[#171717]/50 pt-8 px-4 flex flex-col gap-1">
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={cn(
              "flex items-center gap-3 px-3 py-2 rounded-lg text-[13px] transition-colors",
              activeTab === tab.id
                ? "bg-white/10 text-white font-medium shadow-sm"
                : "text-zinc-400 hover:text-zinc-200 hover:bg-white/[0.03]"
            )}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Content Area */}
      <div className="flex-1 overflow-y-auto p-8 custom-scrollbar bg-[#1c1c1c]">
        <div className="max-w-2xl">
          {/* Header */}
          <h1 className="text-xl font-semibold text-white mb-8">
            {TABS.find(t => t.id === activeTab)?.label}
          </h1>

          {/* Dynamic Content */}
          <div className="space-y-6">
            {activeTab === "general" && <GeneralTab />}
            {activeTab === "appearance" && <AppearanceTab />}
            {activeTab === "behaviour" && <BehaviourTab />}
            {activeTab === "notifications" && <NotificationsTab />}
            {activeTab === "integrations" && <IntegrationsTab />}
            {activeTab === "agents" && <CodingAgentsTab />}
            {activeTab === "shortcuts" && <ShortcutsTab />}
            {activeTab === "dictation" && <DictationTab />}
            {activeTab === "advanced" && <AdvancedTab />}
            {activeTab === "github" && <GithubTab />}
            {activeTab === "workspaces" && <WorkspacesTab />}
            {activeTab === "prompts" && <PromptsTab />}
          </div>
        </div>
      </div>
    </div>
  );
}

function SettingsRow({ label, description, control }: { label: string; description?: string; control: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-white/5 last:border-0 gap-8">
      <div className="flex flex-col gap-1">
        <span className="text-[14px] text-white/90 font-medium">{label}</span>
        {description && <span className="text-[13px] text-zinc-500">{description}</span>}
      </div>
      <div className="shrink-0">{control}</div>
    </div>
  );
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-8">
      <h2 className="text-[11px] font-bold text-zinc-500 uppercase tracking-widest mb-2">{title}</h2>
      <div className="flex flex-col">
        {children}
      </div>
    </div>
  );
}

function GeneralTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title="ACCOUNT">
        {/* Profile Card */}
        <div className="flex items-center justify-between py-4">
          <div className="flex items-center gap-4">
            <div className="h-10 w-10 rounded-full bg-zinc-800 overflow-hidden">
              <img src="https://github.com/shadcn.png" alt="Avatar" className="object-cover" />
            </div>
            <div className="flex flex-col">
              <div className="flex items-center gap-2">
                <span className="text-[14px] text-white font-medium">kid(akira)</span>
                <span className="text-[10px] bg-amber-500/10 text-amber-500 px-1.5 py-0.5 rounded font-medium">Trial</span>
              </div>
              <span className="text-[13px] text-zinc-500">kidiatoliny@akira-io.com</span>
            </div>
          </div>
          <button className="flex items-center gap-2 text-[13px] text-zinc-400 hover:text-white transition-colors">
            <LogOut className="h-4 w-4" />
            Sign out
          </button>
        </div>

        {/* Upgrade Box */}
        <div className="mt-4 p-5 rounded-xl border border-white/5 bg-white/[0.02]">
          <h3 className="text-[14px] text-zinc-400 mb-3">Upgrade for mobile and web access.</h3>
          <ul className="space-y-2 mb-4">
            <li className="flex items-center gap-2 text-[13px] text-zinc-400">
              <span className="text-blue-500">✓</span> Access from mobile, tablet, or any browser
            </li>
            <li className="flex items-center gap-2 text-[13px] text-zinc-400">
              <span className="text-blue-500">✓</span> Start and monitor workspaces on the go
            </li>
          </ul>
          <Button className="w-full bg-blue-500 hover:bg-blue-600 text-white border-0 shadow-lg shadow-blue-500/20">
            Upgrade
          </Button>
        </div>

        <div className="mt-6 border-t border-white/5 pt-2">
          <SettingsRow
            label="Launch at login"
            description="Automatically start Polyscope when you log in. It will run in the menubar so the server is always available."
            control={<Switch />}
          />
        </div>
      </SettingsSection>
    </div>
  );
}

function AppearanceTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Sync with system"
        description="Automatically switch between dark and light themes based on your system appearance."
        control={<Switch />}
      />
      <SettingsRow
        label="Theme"
        description="Choose a color theme for the interface."
        control={
          <Select defaultValue="dark">
            <SelectTrigger className="w-40 h-8 bg-white/5 border-white/10 text-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="dark">Default Dark</SelectItem>
              <SelectItem value="light">Light</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingsRow
        label="Zoom"
        description="Adjust the interface zoom level. ⌘+/⌘-"
        control={
          <div className="flex items-center gap-3">
            <button className="text-zinc-500 hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-white/10"><Minus className="h-3 w-3" /></button>
            <span className="text-[13px] text-white w-10 text-center font-medium">100%</span>
            <button className="text-zinc-500 hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-white/10"><Plus className="h-3 w-3" /></button>
          </div>
        }
      />
      <SettingsRow
        label="Terminal font"
        description="Custom font family for the built-in terminal. Useful for nerd fonts with icon support. Leave empty to use the default font."
        control={
          <input
            type="text"
            placeholder="e.g. MesloLGS NF"
            className="w-48 h-8 px-3 rounded-md bg-white/5 border border-white/10 text-[13px] text-white placeholder:text-zinc-600 focus:outline-none focus:border-purple-500 transition-colors"
          />
        }
      />
    </div>
  );
}

function BehaviourTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Hide inactive repositories"
        description="Only show repositories that have active workspaces in the sidebar."
        control={<Switch />}
      />
      <SettingsRow
        label="Sidebar sort order"
        description="Choose how workspaces are organized in the sidebar."
        control={
          <Select defaultValue="repository">
            <SelectTrigger className="w-40 h-8 bg-white/5 border-white/10 text-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="repository">Repository</SelectItem>
              <SelectItem value="recent">Recent</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingsRow
        label="Send review comments immediately"
        description="Send diff comments directly to the agent when you submit them. When off, comments are pasted into the prompt input when you close the diff."
        control={<Switch defaultChecked />}
      />
      <SettingsRow
        label="Show inline diff comment responses"
        description="Display the assistant response directly under sent diff comments. Responses stay collapsed by default."
        control={<Switch />}
      />
      <SettingsRow
        label="Default Merge Action"
        description='The primary action shown on the merge button. "Merge locally" merges into the base branch only. "Merge and push" also pushes to the remote.'
        control={
          <Select defaultValue="draft_pr">
            <SelectTrigger className="w-44 h-8 bg-white/5 border-white/10 text-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="draft_pr">Draft pull request</SelectItem>
              <SelectItem value="merge_locally">Merge locally</SelectItem>
              <SelectItem value="merge_push">Merge and push</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <SettingsRow
        label="Fetch latest from origin"
        description="When enabled, new workspaces start from the latest remote state. When disabled, they start from the current local base branch."
        control={<Switch defaultChecked />}
      />
      <SettingsRow
        label="Auto-archive workspaces"
        description="Automatically remove workspaces after merging or creating a PR, once CI passes."
        control={<Switch />}
      />
    </div>
  );
}

function NotificationsTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Notify when agent finishes"
        description="Show a native notification when an agent completes its work and the app is not focused."
        control={<Switch defaultChecked />}
      />
      <SettingsRow
        label="Dock badge"
        description="Show the number of workspaces needing attention as a badge on the dock icon."
        control={<Switch defaultChecked />}
      />

      <div className="border-t border-white/5 pt-2 mt-2">
        <SettingsRow
          label="Completion sound"
          description="Play a sound when an agent completes its work."
          control={
            <Select defaultValue="unfocused">
              <SelectTrigger className="w-48 h-8 bg-white/5 border-white/10 text-white">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="unfocused">When not focused</SelectItem>
                <SelectItem value="always">Always</SelectItem>
                <SelectItem value="never">Never</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsRow
          label="Sound"
          description="Choose which notification sound to play."
          control={
            <Select defaultValue="sparkle">
              <SelectTrigger className="w-48 h-8 bg-white/5 border-white/10 text-white">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="sparkle">Sparkle Ding</SelectItem>
                <SelectItem value="chime">Chime</SelectItem>
                <SelectItem value="pop">Pop</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </div>
    </div>
  );
}

function IntegrationsTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Nightwatch"
        description="Laravel error tracking"
        control={
          <Button variant="ghost" className="h-8 gap-2 bg-white/5 hover:bg-white/10 text-zinc-300">
            <Unplug className="h-4 w-4" /> Disconnect
          </Button>
        }
      />
      <SettingsRow
        label="Sentry"
        description="Error tracking and performance monitoring"
        control={
          <Button variant="ghost" className="h-8 gap-2 bg-white/5 hover:bg-white/10 text-zinc-300">
            <Link2 className="h-4 w-4" /> Connect
          </Button>
        }
      />
      <div className="border-t border-white/5 pt-2 mt-2">
        <SettingsRow
          label="Default IDE"
          description="Used by the Command Palette action for opening the current workspace."
          control={
            <Select defaultValue="phpstorm">
              <SelectTrigger className="w-32 h-8 bg-white/5 border-white/10 text-white">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="phpstorm">PhpStorm</SelectItem>
                <SelectItem value="vscode">VS Code</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsRow
          label="Default Terminal"
          description="Used when opening a workspace in a terminal."
          control={
            <Select defaultValue="ghostty">
              <SelectTrigger className="w-32 h-8 bg-white/5 border-white/10 text-white">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ghostty">Ghostty</SelectItem>
                <SelectItem value="iterm">iTerm</SelectItem>
                <SelectItem value="terminal">Terminal</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </div>
    </div>
  );
}

function CodingAgentsTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <span className="text-[14px] text-white/90 font-medium">Environment Variables</span>
          <span className="text-[13px] text-zinc-500 leading-relaxed">
            Configure environment variables that will be passed to Claude Code. One per line, format: <code className="bg-white/5 px-1.5 rounded py-0.5 font-mono text-[11px]">VAR_NAME=value</code> or <code className="bg-white/5 px-1.5 rounded py-0.5 font-mono text-[11px]">export VAR_NAME=value</code>
          </span>
        </div>

        <textarea
          className="w-full h-40 bg-white/[0.03] border border-white/5 rounded-xl text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-white/20 transition-colors custom-scrollbar"
          defaultValue={`ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=us-east-1
AWS_PROFILE=default`}
        />
      </div>
    </div>
  );
}

function ShortcutsTab() {
  const ShortcutRow = ({ label, keys }: { label: string; keys: string }) => (
    <div className="flex items-center justify-between py-2">
      <span className="text-[13px] text-white/90">{label}</span>
      <div className="w-48">
        <div className="bg-white/5 border border-white/10 rounded h-8 px-4 flex items-center justify-center font-mono text-[12px] text-zinc-300 tracking-widest">
          {keys}
        </div>
      </div>
    </div>
  );

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title="KEYBOARD SHORTCUTS">
        <ShortcutRow label="Toggle Terminal" keys="⌘`" />
        <ShortcutRow label="Toggle Sidebar" keys="⌘B" />
        <ShortcutRow label="Toggle Changes Panel" keys="⌘D" />
        <ShortcutRow label="Toggle Diff View" keys="⌘⇧D" />
        <ShortcutRow label="Toggle Preview" keys="⌘P" />
        <ShortcutRow label="Merge / Pull Request" keys="⌘⇧M" />
        <ShortcutRow label="Add Attachment" keys="⌘⇧A" />
        <ShortcutRow label="Toggle Plan Mode" keys="⌘⇧P" />
        <ShortcutRow label="Toggle Opinions" keys="⌘⇧O" />
        <ShortcutRow label="Toggle Dictation" keys="⌘⇧V" />
        <ShortcutRow label="Focus Prompt Input" keys="⌘L" />
      </SettingsSection>
    </div>
  );
}

function DictationTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <div className="flex flex-col gap-1 mb-6">
        <span className="text-[14px] text-white/90 font-medium">Dictation</span>
        <span className="text-[13px] text-zinc-500">Choose the speech recognition method for prompt dictation.</span>
      </div>

      <SettingsRow
        label="Speech Recognition Method"
        control={
          <Select defaultValue="web_speech">
            <SelectTrigger className="w-40 h-8 bg-white/5 border-white/10 text-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="web_speech">Web Speech</SelectItem>
              <SelectItem value="custom">Custom Engine</SelectItem>
            </SelectContent>
          </Select>
        }
      />
      <p className="text-[13px] text-zinc-500 mt-2">
        Uses the built-in speech recognition capabilities of your operating system. Lower accuracy and limited language support. No data will be sent to any servers.
      </p>
    </div>
  );
}

function AdvancedTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Show all agent events (debug)"
        description="Shows raw agent and ask-user events in the activity feed."
        control={<Switch />}
      />
    </div>
  );
}

function GithubTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="GitHub Authentication"
        description="Connect your GitHub account to enable advanced features."
        control={
          <Button variant="ghost" className="h-8 gap-2 bg-white/5 hover:bg-white/10 text-zinc-300">
            <Link2 className="h-4 w-4" /> Connect
          </Button>
        }
      />
    </div>
  );
}

function WorkspacesTab() {
  return (
    <div className="animate-in fade-in duration-300">
      <SettingsRow
        label="Default Workspace Directory"
        description="Where new clone operations will store files locally."
        control={
          <input
            type="text"
            defaultValue="~/Developer/Akira"
            className="w-64 h-8 px-3 rounded-md bg-white/5 border border-white/10 text-[13px] text-white focus:outline-none focus:border-purple-500 transition-colors"
          />
        }
      />
    </div>
  );
}

function PromptTextarea({ label, defaultText, helpText }: { label: string, defaultText: string, helpText: string }) {
  return (
    <div className="flex flex-col gap-3 mb-8">
      <span className="text-[14px] text-white/90 font-medium">{label}</span>
      <textarea
        className="w-full h-48 bg-white/[0.03] border border-white/5 rounded-xl text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-white/20 transition-colors custom-scrollbar"
        defaultValue={defaultText}
      />
      <span className="text-[12px] text-zinc-500 leading-relaxed pr-8">
        {helpText}
      </span>
    </div>
  );
}

function PromptsTab() {
  const mergePrompt = `Merge the changes from this worktree into the base branch locally.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const mergePushPrompt = `Merge the changes from this worktree into the base branch and push to the remote.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const prPrompt = `Create a pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const draftPrPrompt = `Create a draft pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  return (
    <div className="animate-in fade-in duration-300">
      <PromptTextarea
        label="Merge Prompt"
        defaultText={mergePrompt}
        helpText="Showing the default local merge prompt. This merges locally only — it does not push to the remote. Edit to customize."
      />
      <PromptTextarea
        label="Merge and Push Prompt"
        defaultText={mergePushPrompt}
        helpText="Showing the default merge-and-push prompt. This merges locally and pushes to the remote. Edit to customize."
      />
      <PromptTextarea
        label="Pull Request Prompt"
        defaultText={prPrompt}
        helpText="Showing the default PR prompt. The branch name and issue details are filled in per workspace at runtime. Edit to customize."
      />
      <PromptTextarea
        label="Draft Pull Request Prompt"
        defaultText={draftPrPrompt}
        helpText="Showing the default draft PR prompt. The branch name and issue details are filled in per workspace at runtime. Edit to customize."
      />
    </div>
  );
}
