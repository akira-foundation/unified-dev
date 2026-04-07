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
    <div className="grid grid-cols-1 gap-8 lg:grid-cols-3">
      <div className="lg:col-span-2 space-y-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <div className="space-y-1">
              <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
                {t("agenda.history.title")}
              </CardTitle>
              <CardDescription className="text-[10px] font-bold uppercase tracking-widest text-zinc-500/80">
                {t("agenda.history.subtitle")}
              </CardDescription>
            </div>
            <Button variant="ghost" size="sm" className="text-[10px] font-bold uppercase tracking-widest h-8 px-3">
              {t("agenda.viewAll")}
            </Button>
          </CardHeader>
          <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
            {agendaItems.length === 0 ? (
              <div className="flex items-center justify-center py-10">
                <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">
                  {t("agenda.empty")}
                </p>
              </div>
            ) : (
              <div className="divide-y divide-zinc-100 dark:divide-zinc-800/50">
                {agendaItems.map((item) => (
                  <div
                    key={item.id}
                    className="flex items-center gap-4 px-6 py-4 hover:bg-zinc-50/50 dark:hover:bg-zinc-900/10 transition-colors group cursor-pointer"
                  >
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100 truncate mb-0.5">
                        {item.title}
                      </h4>
                      <p className="text-xs text-zinc-500 dark:text-zinc-400 truncate">{item.subtitle}</p>
                    </div>

                    <div className="hidden sm:flex items-center gap-1.5 text-[11px] font-medium text-zinc-400 dark:text-zinc-600 shrink-0">
                      <Clock size={12} className="opacity-70" />
                      {item.syncDate.toLocaleDateString(locale, { day: "numeric", month: "short" })},{" "}
                      {item.syncDate.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" })}
                    </div>

                    <ChevronRight className="h-4 w-4 text-zinc-300 dark:text-zinc-600 group-hover:text-zinc-500 group-hover:translate-x-0.5 transition-all" />
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
            {t("agenda.summary.title")}
          </CardTitle>
          <CardDescription className="text-[10px] font-bold uppercase tracking-widest text-zinc-500/80">
            {formatWeekLabel(weekStart, weekEnd, locale)}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6 p-6 pt-6">
          <div className="space-y-6">
            <SummaryBar
              label={t("agenda.summary.syncs")}
              value={syncsThisWeek}
              max={maxSummaryValue}
              barClass="bg-purple-500 dark:bg-purple-500/80 shadow-[0_0_12px_rgba(168,85,247,0.4)]"
            />
            <SummaryBar
              label={t("agenda.summary.repos")}
              value={reposCount}
              max={Math.max(reposCount, 1)}
              barClass="bg-blue-500 dark:bg-blue-500/80 shadow-[0_0_12px_rgba(59,130,246,0.4)]"
            />
          </div>

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
      <div className="flex justify-between items-end mb-2">
        <span className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-500">{label}</span>
        <span className="text-lg font-black text-zinc-900 dark:text-white leading-none">{value}</span>
      </div>
      <div className="h-1.5 w-full rounded-full bg-zinc-100 dark:bg-zinc-800/50">
        <div className={cn("h-full rounded-full transition-all duration-500", barClass)} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}
