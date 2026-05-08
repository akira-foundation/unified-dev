import { useMemo } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useI18n } from "@/i18n/i18n";
import { useOssCalendar } from "@/hooks/useOpenSource";
import { cn } from "@/lib/utils";

interface ContributionCalendarProps {
  year?: number;
}

const COLORS = [
  "bg-zinc-100 dark:bg-zinc-800",
  "bg-emerald-200 dark:bg-emerald-900",
  "bg-emerald-400 dark:bg-emerald-700",
  "bg-emerald-500 dark:bg-emerald-500",
  "bg-emerald-600 dark:bg-emerald-400",
];

function intensity(count: number): number {
  if (count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  if (count <= 9) return 3;
  return 4;
}

export function ContributionCalendar({ year }: ContributionCalendarProps) {
  const { t } = useI18n();
  const { data, isLoading } = useOssCalendar(year);

  const weeks = useMemo(() => {
    if (!data) return [];
    const grouped: Array<typeof data> = [];
    let week: typeof data = [];
    for (const day of data) {
      const weekday = new Date(day.date).getDay();
      if (weekday === 0 && week.length > 0) {
        grouped.push(week);
        week = [];
      }
      week.push(day);
    }
    if (week.length > 0) grouped.push(week);
    return grouped;
  }, [data]);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-semibold">{t("openSource.calendar.title")}</CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto p-4">
        {isLoading ? (
          <Skeleton className="h-32 w-full" />
        ) : (
          <div className="flex gap-1">
            {weeks.map((week, wi) => (
              <div key={wi} className="flex flex-col gap-1">
                {week.map((day) => (
                  <div
                    key={day.date}
                    title={`${day.date}: ${day.count}`}
                    className={cn("h-3 w-3 rounded-sm", COLORS[intensity(day.count)])}
                  />
                ))}
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
