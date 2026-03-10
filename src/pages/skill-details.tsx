import { ArrowLeft, ExternalLink, Terminal, Sparkles, Trash2, ShieldOff, Info, TerminalSquare, Box } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "@/components/layout/page-header";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { cn } from "@/lib/utils";

export function SkillDetailsPage() {
  const { selectedSkill, setActiveTab } = useAgentsStore();

  if (!selectedSkill) {
    setActiveTab("skills");
    return null;
  }

  const SettingsSection = ({ title, description, children, icon: Icon }: any) => (
    <Card className="mb-6">
      <CardHeader className="flex flex-row items-center gap-3 space-y-0">
        {Icon && (
          <div className="h-10 w-10 flex items-center justify-center rounded-md bg-purple-500/10 text-purple-500 shrink-0">
            <Icon className="h-5 w-5" />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl">{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </div>
      </CardHeader>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 gap-0 p-0">
        {children}
      </CardContent>
    </Card>
  );

  const SettingsItem = ({ label, description, action, className }: any) => (
    <div className={cn("flex flex-col gap-3 px-6 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40", className)}>
      <div className="flex items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
          {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
        </div>
        {action && <div className="shrink-0">{action}</div>}
      </div>
    </div>
  );

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-3xl px-6">
        <div className="flex flex-col gap-4">
          <button
            onClick={() => setActiveTab("skills")}
            className="flex items-center gap-2 text-zinc-500 hover:text-white transition-colors w-fit group"
          >
            <ArrowLeft className="h-4 w-4 transition-transform group-hover:-translate-x-1" />
            <span className="text-sm font-medium">Back to Skills</span>
          </button>
          <div className="flex items-center gap-4">
            <div className={cn("h-12 w-12 rounded-md flex items-center justify-center text-2xl shadow-inner shrink-0", selectedSkill.icon)}>
              <Sparkles className="h-6 w-6" />
            </div>
            <div>
              <PageHeaderTitle className="text-3xl">{selectedSkill.title}</PageHeaderTitle>
              <PageHeaderMeta className="flex items-center gap-3">
                <button className="flex items-center gap-1.5 text-xs hover:text-zinc-300 transition-colors">
                  Open folder <ExternalLink className="h-3 w-3" />
                </button>
                <span className="text-zinc-700">•</span>
                <Badge variant="outline" className="text-[10px] uppercase tracking-wider font-black px-2 py-0 h-5 border-white/5 bg-white/5 text-zinc-500">
                  v2.0.4
                </Badge>
              </PageHeaderMeta>
            </div>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-24 flex flex-col">
        <SettingsSection
          title="General"
          description="Basic information and documentation for this skill."
          icon={Info}
        >
          <SettingsItem
            label="Description"
            description={`${selectedSkill.description}. Activate when implementing authentication features including login, registration, password reset, email verification, two-factor authentication (2FA/TOTP), profile updates, headless auth, authentication scaffolding, or auth guards in Laravel applications.`}
          />
          <SettingsItem
            label="Documentation"
            description="Access the full reference and usage patterns for this module."
            action={
              <div className="flex items-center gap-2 text-sm text-zinc-300">
                <code className="px-1.5 py-0.5 rounded bg-white/5 border border-white/5 text-xs font-mono text-purple-400">search-docs</code>
              </div>
            }
          />
        </SettingsSection>

        <SettingsSection
          title="Usage & Integration"
          description="How to interface with this skill in your workspace."
          icon={TerminalSquare}
        >
          {[
            { label: "Routes", code: "list-routes", meta: "only_vendor: true" },
            { label: "Actions", path: "app/Actions/Fortify/" },
            { label: "Config", path: "config/fortify.php" },
          ].map((item, i) => (
            <SettingsItem
              key={i}
              label={item.label}
              description={`Interface with ${item.label.toLowerCase()} using the following commands or paths.`}
              action={
                <div className="flex items-center gap-2">
                  {item.code && <code className="px-1.5 py-0.5 rounded bg-white/5 border border-white/5 text-[11px] font-mono text-purple-400">{item.code}</code>}
                  {item.path && <code className="mx-1.5 px-1.5 py-0.5 rounded bg-white/5 border border-white/5 text-[11px] font-mono text-zinc-300">{item.path}</code>}
                  {item.meta && <span>with <code className="mx-1.5 px-1.5 py-0.5 rounded bg-white/5 border border-white/5 text-[11px] font-mono text-zinc-300">{item.meta}</code> and action: "Fortify"</span>}
                </div>
              }
            />
          ))}
        </SettingsSection>

        <SettingsSection
          title="Capabilities"
          description="Functional features provided by this skill."
          icon={Box}
        >
          <SettingsItem
            label="Available Features"
            description="List of core features this skill can execute."
            action={
              <div className="flex flex-wrap gap-2 justify-end max-w-xs">
                {["AUTH_GUARDS", "HEADLESS_AUTH", "TWO_FACTOR"].map(tag => (
                  <Badge key={tag} variant="secondary" className="bg-white/5 hover:bg-white/10 text-zinc-400 border-none px-3 py-1 text-[10px]">
                    {tag}
                  </Badge>
                ))}
              </div>
            }
          />
        </SettingsSection>

        <div className="flex items-center justify-between pt-4">
          <div className="flex items-center gap-3">
            <Button
              variant="outline"
              className="border-red-500/20 hover:bg-red-500/10 text-red-500 h-11 px-6 font-bold gap-2 rounded-md"
            >
              <Trash2 className="h-4 w-4" /> Uninstall
            </Button>
            <Button
              variant="outline"
              className="border-white/10 hover:bg-white/5 text-zinc-300 h-11 px-6 font-bold gap-2 rounded-md"
            >
              <ShieldOff className="h-4 w-4" /> Disable
            </Button>
          </div>
          <Button className="h-11 px-8 gap-2 font-bold shadow-lg shadow-primary/20 bg-primary hover:bg-primary/90 text-white border-0 rounded-md">
            <Terminal className="h-4 w-4" /> Try executing
          </Button>
        </div>
      </div>
    </PageLayout>
  );
}
