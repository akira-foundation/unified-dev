import { ArrowLeft, Info, Clock as ClockIcon, Settings, Bot } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "@/components/layout/page-header";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { SettingsSection } from "@/components/settings/settings-section";

export function CreateAutomationPage() {
  const { t } = useI18n();
  const { setActiveTab, selectedAutomation } = useAgentsStore();

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
            className="flex items-center gap-2 text-zinc-500 hover:text-foreground transition-colors w-fit group"
          >
            <ArrowLeft className="h-4 w-4 transition-transform group-hover:-translate-x-1" />
            <span className="text-sm font-medium">{t("pages.createAutomation.back")}</span>
          </button>
          <div>
            <PageHeaderTitle>
              {selectedAutomation ? t("pages.createAutomation.titleConfigure") : t("pages.createAutomation.titleCreate")}
            </PageHeaderTitle>
            <PageHeaderMeta>
              <span>{t("pages.createAutomation.subtitle")}</span>
            </PageHeaderMeta>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-12 flex flex-col gap-8">
        {/* Info Box */}
        <div className="flex gap-4 p-5 rounded-md bg-blue-500/5 border border-blue-500/10 text-sm">
          <Info className="h-5 w-5 text-blue-500 shrink-0 mt-0.5" />
          <p className="leading-relaxed dark:text-zinc-300 text-foreground/70 text-[13px]">
            {t("pages.createAutomation.infoBox")}
          </p>
        </div>

        <form onSubmit={(e) => e.preventDefault()}>
          <SettingsSection
            title={t("pages.createAutomation.generalInfo.title")}
            description={t("pages.createAutomation.generalInfo.description")}
            icon={Settings}
          >
            <SettingsItem
              label={t("pages.createAutomation.name.label")}
              description={t("pages.createAutomation.name.description")}
              action={
                <Input
                  defaultValue={selectedAutomation?.text ? `Auto: ${selectedAutomation.text.split(' ').slice(0, 3).join(' ')}...` : ""}
                  placeholder={t("pages.createAutomation.name.placeholder")}
                  className="w-64"
                />
              }
            />
            <SettingsItem
              label={t("pages.createAutomation.projects.label")}
              description={t("pages.createAutomation.projects.description")}
              action={
                <Input
                  placeholder={t("pages.createAutomation.projects.placeholder")}
                  className="w-64"
                />
              }
            />
            <SettingsItem
              label={t("pages.createAutomation.executionEnv.label")}
              description={t("pages.createAutomation.executionEnv.description")}
              action={
                <Tabs defaultValue="worktree">
                  <TabsList className="rounded-md">
                    <TabsTrigger value="worktree" className="rounded-md">{t("pages.createAutomation.executionEnv.worktree")}</TabsTrigger>
                    <TabsTrigger value="local" className="rounded-md">{t("pages.createAutomation.executionEnv.local")}</TabsTrigger>
                  </TabsList>
                </Tabs>
              }
            />
          </SettingsSection>

          <SettingsSection
            title={t("pages.createAutomation.agentConfig.title")}
            description={t("pages.createAutomation.agentConfig.description")}
            icon={Bot}
          >
            <SettingsItem
              label={t("pages.createAutomation.prompt.label")}
              description={t("pages.createAutomation.prompt.description")}
            >
              <textarea
                defaultValue={selectedAutomation?.text || ""}
                placeholder={t("pages.createAutomation.prompt.placeholder")}
                rows={4}
                className="w-full rounded-md border border-input bg-transparent p-4 text-[13px] text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 transition-all custom-scrollbar resize-none font-sans"
              />
            </SettingsItem>

            <SettingsItem
              label={t("pages.createAutomation.schedule.label")}
              description={t("pages.createAutomation.schedule.description")}
              action={
                <Tabs defaultValue="daily">
                  <TabsList>
                    <TabsTrigger value="daily">{t("pages.createAutomation.schedule.daily")}</TabsTrigger>
                    <TabsTrigger value="interval">{t("pages.createAutomation.schedule.interval")}</TabsTrigger>
                  </TabsList>
                </Tabs>
              }
            >
              <div className="flex flex-wrap items-center gap-4 mt-2">
                <div className="relative w-32">
                  <Input
                    defaultValue="09:00"
                    className="pr-10 font-mono text-[13px]"
                  />
                  <ClockIcon className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
                </div>
                <div className="flex gap-1.5">
                  {['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map(day => (
                    <button key={day} className="h-8 w-8 rounded-md dark:bg-white dark:text-black bg-zinc-100 text-foreground font-black text-[9px] hover:bg-zinc-200 transition-all shadow-sm">
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
              {t("common.cancel")}
            </Button>
            <Button className="font-bold px-8">
              {t("pages.createAutomation.submit")}
            </Button>
          </div>
        </form>
      </div>
    </PageLayout>
  );
}
