import { ArrowLeft, Info, Clock as ClockIcon, Settings, Bot } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "@/components/layout/page-header";
import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";

export function CreateAutomationPage() {
  const { setActiveTab, selectedAutomation } = useAgentsStore();

  const SettingsSection = ({ title, description, children, icon: Icon }: any) => (
    <Card className="mb-6 overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center gap-4 px-6 py-6 pb-6">
        {Icon && (
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Icon size={22} strokeWidth={2} />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{title}</CardTitle>
          {description && <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">{description}</CardDescription>}
        </div>
      </div>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
        {children}
      </CardContent>
    </Card>
  );

  const SettingsItem = ({ label, description, action, className, children }: any) => (
    <div
      className={cn(
        "flex flex-col gap-4 px-6 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40",
        className,
      )}
    >
      <div className="flex items-center justify-between gap-4">
        <div className="flex flex-col gap-1 w-full max-w-[65%]">
          <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
          {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
        </div>
        <div className="shrink-0">{action}</div>
      </div>
      {children}
    </div>
  );

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-3xl px-6">
        <div className="flex flex-col gap-4">
          <button
            onClick={() => setActiveTab("automations")}
            className="flex items-center gap-2 text-zinc-500 hover:text-white transition-colors w-fit group"
          >
            <ArrowLeft className="h-4 w-4 transition-transform group-hover:-translate-x-1" />
            <span className="text-sm font-medium">Back to Automations</span>
          </button>
          <div>
            <PageHeaderTitle className="text-3xl">
              {selectedAutomation ? "Configure automation" : "Create automation"}
            </PageHeaderTitle>
            <PageHeaderMeta>
              <span>Automate recurring tasks in the background.</span>
            </PageHeaderMeta>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-12 flex flex-col gap-8">
        {/* Info Box */}
        <div className="flex gap-4 p-5 rounded-md bg-blue-500/5 border border-blue-500/10 text-sm">
          <Info className="h-5 w-5 text-blue-500 shrink-0 mt-0.5" />
          <p className="leading-relaxed text-zinc-300 text-[13px]">
            Automations run with your default sandbox settings. Tool calls will fail if they require modifying files outside the workspace, accessing network, or working with apps on your computer.
          </p>
        </div>

        <form onSubmit={(e) => e.preventDefault()}>
          <SettingsSection
            title="General Information"
            description="Basic configuration for your automation thread."
            icon={Settings}
          >
            <SettingsItem
              label="Name"
              description="Choose a descriptive name for this automation."
              action={
                <Input
                  defaultValue={selectedAutomation?.text ? `Auto: ${selectedAutomation.text.split(' ').slice(0, 3).join(' ')}...` : ""}
                  placeholder="Check for sentry issues"
                  className="w-64 bg-black/20 border-white/5 rounded-md"
                />
              }
            />
            <SettingsItem
              label="Projects"
              description="Specify which folders or repositories this automation should monitor."
              action={
                <Input
                  placeholder="Choose a folder"
                  className="w-64 bg-black/20 border-white/5 rounded-md"
                />
              }
            />
            <SettingsItem
              label="Execution environment"
              description="Where the automation tasks will be executed by the agent."
              action={
                <Tabs defaultValue="worktree">
                  <TabsList className="bg-black/20 border border-white/5 rounded-md">
                    <TabsTrigger value="worktree" className="rounded-md">Worktree</TabsTrigger>
                    <TabsTrigger value="local" className="rounded-md">Local</TabsTrigger>
                  </TabsList>
                </Tabs>
              }
            />
          </SettingsSection>

          <SettingsSection
            title="Agent Configuration"
            description="Define the instructions and schedule for the automation."
            icon={Bot}
          >
            <SettingsItem
              label="Prompt"
              description="The core instructions for the agent. Use $variable syntax for integrations."
            >
              <textarea
                defaultValue={selectedAutomation?.text || ""}
                placeholder="look for crashes in $Sentry"
                rows={4}
                className="w-full rounded-md bg-black/20 border border-white/5 p-4 text-[13px] text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-all custom-scrollbar resize-none font-sans"
              />
            </SettingsItem>

            <SettingsItem
              label="Schedule"
              description="How often should this automation run?"
              action={
                <Tabs defaultValue="daily">
                  <TabsList className="bg-black/20 border border-white/5">
                    <TabsTrigger value="daily">Daily</TabsTrigger>
                    <TabsTrigger value="interval">Interval</TabsTrigger>
                  </TabsList>
                </Tabs>
              }
            >
              <div className="flex flex-wrap items-center gap-4 mt-2">
                <div className="relative w-32">
                  <Input
                    defaultValue="09:00"
                    className="bg-black/20 border-white/5 pr-10 text-zinc-200 transition-all font-mono text-[13px]"
                  />
                  <ClockIcon className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
                </div>
                <div className="flex gap-1.5">
                  {['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map(day => (
                    <button key={day} className="h-8 w-8 rounded-md bg-white text-black font-black text-[9px] hover:bg-zinc-200 transition-all shadow-sm">
                      {day}
                    </button>
                  ))}
                </div>
              </div>
            </SettingsItem>
          </SettingsSection>

          <div className="flex justify-end gap-3 mt-8">
            <Button
              variant="ghost"
              onClick={() => setActiveTab("automations")}
              className="font-bold"
            >
              Cancel
            </Button>
            <Button className="font-bold px-8">
              Create automation
            </Button>
          </div>
        </form>
      </div>
    </PageLayout>
  );
}
