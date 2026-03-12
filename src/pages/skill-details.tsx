import { ArrowLeft, Sparkles, Info } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle } from "@/components/layout/page-header";
import { Card, CardContent, CardTitle, CardDescription } from "@/components/ui/card";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { cn } from "@/lib/utils";

export function SkillDetailsPage() {
  const { selectedSkill, setActiveTab } = useAgentsStore();

  if (!selectedSkill) {
    setActiveTab("skills");
    return null;
  }

  const displayName: string = selectedSkill.name ?? selectedSkill.title ?? selectedSkill.id;
  const displayDescription: string = selectedSkill.description ?? "";
  const iconClass: string = selectedSkill.icon ?? "";
  const sourcePath: string | null = selectedSkill.source_path ?? null;

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
            <div className={cn("h-12 w-12 rounded-md flex items-center justify-center text-2xl shadow-inner shrink-0 bg-white/5 border border-white/5", iconClass)}>
              <Sparkles className="h-6 w-6" />
            </div>
            <div>
              <PageHeaderTitle className="text-3xl">{displayName}</PageHeaderTitle>
            </div>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-24 flex flex-col">
        <SettingsSection
          title="General"
          description="Basic information about this skill."
          icon={Info}
        >
          {displayDescription ? (
            <SettingsItem
              label="Description"
              description={displayDescription}
            />
          ) : null}
          {sourcePath ? (
            <SettingsItem
              label="Location"
              description={sourcePath}
            />
          ) : null}
        </SettingsSection>
      </div>
    </PageLayout>
  );
}
