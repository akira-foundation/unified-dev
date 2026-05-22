import { useMemo } from "react";
import { ChevronRight, Clock } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import type { OrganizationSummary, OrganizationRepoWithOrg } from "@/types/organization";

interface AgendaViewProps {
  organizations: OrganizationSummary[];
  allRepos: OrganizationRepoWithOrg[];
}

interface AgendaItem {
  id: string;
  title: string;
  subtitle: string;
  syncDate: Date;
}

function getWeekRange(): { start: Date; end: Date } {
  const now = new Date();
  const day = now.getDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  const monday = new Date(now);
  monday.setDate(now.getDate() + diffToMonday);
  monday.setHours(0, 0, 0, 0);
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { start: monday, end: sunday };
}

function formatWeekLabel(start: Date, end: Date, locale: string): string {
  const month = start.toLocaleDateString(locale, { month: "long" });
  return `${start.getDate()} a ${end.getDate()} de ${month.charAt(0).toUpperCase()}${month.slice(1)}`;
}


export function AgendaView({ organizations, allRepos }: AgendaViewProps) {
  const { t, locale } = useI18n();
  const { start: weekStart, end: weekEnd } = getWeekRange();

  const agendaItems = useMemo<AgendaItem[]>(() => {
    return [...organizations]
      .filter((org) => org.last_synced_at !== null)
      .sort((a, b) =>
        new Date(b.last_synced_at!).getTime() - new Date(a.last_synced_at!).getTime(),
      )
      .slice(0, 5)
      .map((org) => ({
        id: org.id,
        title: org.name,
        subtitle: `${org.selected_repos_count} ${org.selected_repos_count === 1 ? "repositório" : "repositórios"}`,
        syncDate: new Date(org.last_synced_at!),
      }));
  }, [organizations]);

  const syncsThisWeek = useMemo(
    () =>
      organizations.filter((org) => {
        if (!org.last_synced_at) return false;
        const d = new Date(org.last_synced_at);
        return d >= weekStart && d <= weekEnd;
      }).length,
    [organizations, weekStart, weekEnd],
  );

  const reposCount = allRepos.length;
  const maxSummaryValue = Math.max(organizations.length, 1);

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <div className="lg:col-span-2">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <div>
              <CardTitle className="text-[13px] font-semibold text-foreground">
                {t("agenda.history.title")}
              </CardTitle>
              <CardDescription className="text-xs text-muted-foreground">
                {t("agenda.history.subtitle")}
              </CardDescription>
            </div>
            <Button variant="ghost" size="sm" className="h-7 px-2 text-xs text-muted-foreground">
              {t("agenda.viewAll")}
            </Button>
          </CardHeader>
          <CardContent className="border-t border-zinc-100 px-0 dark:border-zinc-800/60">
            {agendaItems.length === 0 ? (
              <div className="flex items-center justify-center py-8">
                <p className="text-sm italic text-zinc-400 dark:text-zinc-500">{t("agenda.empty")}</p>
              </div>
            ) : (
              <div className="divide-y divide-zinc-100 dark:divide-zinc-800/60">
                {agendaItems.map((item) => (
                  <div
                    key={item.id}
                    className="group flex cursor-pointer items-center gap-3 px-4 py-2.5 transition-colors hover:bg-zinc-50/60 dark:hover:bg-zinc-900/20"
                  >
                    <div className="min-w-0 flex-1">
                      <h4 className="truncate text-[13px] font-medium text-zinc-900 dark:text-zinc-100">{item.title}</h4>
                      <p className="truncate text-xs text-zinc-500 dark:text-zinc-500">{item.subtitle}</p>
                    </div>
                    <div className="hidden shrink-0 items-center gap-1.5 text-xs text-zinc-400 dark:text-zinc-600 sm:flex">
                      <Clock size={12} className="opacity-70" />
                      {item.syncDate.toLocaleDateString(locale, { day: "numeric", month: "short" })},{" "}
                      {item.syncDate.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" })}
                    </div>
                    <ChevronRight className="h-4 w-4 text-zinc-300 transition-all group-hover:translate-x-0.5 group-hover:text-zinc-500 dark:text-zinc-600" />
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-[13px] font-semibold text-foreground">{t("agenda.summary.title")}</CardTitle>
          <CardDescription className="text-xs text-muted-foreground">
            {formatWeekLabel(weekStart, weekEnd, locale)}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4 px-4 pb-4">
          <SummaryBar label={t("agenda.summary.syncs")} value={syncsThisWeek} max={maxSummaryValue} barClass="bg-purple-500" />
          <SummaryBar label={t("agenda.summary.repos")} value={reposCount} max={Math.max(reposCount, 1)} barClass="bg-blue-500" />
        </CardContent>
      </Card>
    </div>
  );
}

function SummaryBar({
  label,
  value,
  max,
  barClass,
}: {
  label: string;
  value: number;
  max: number;
  barClass: string;
}) {
  const pct = max > 0 ? Math.min((value / max) * 100, 100) : 0;
  return (
    <div>
      <div className="mb-1.5 flex items-end justify-between">
        <span className="text-xs font-medium text-zinc-500 dark:text-zinc-400">{label}</span>
        <span className="text-base font-semibold leading-none text-zinc-900 dark:text-white">{value}</span>
      </div>
      <div className="h-1.5 w-full rounded-full bg-zinc-100 dark:bg-zinc-800/60">
        <div className={cn("h-full rounded-full transition-all duration-500", barClass)} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}
