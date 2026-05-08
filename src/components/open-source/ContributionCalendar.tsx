import { useMemo } from "react";

import { Skeleton } from "@/components/ui/skeleton";
import { useOssCalendar } from "@/hooks/useOpenSource";
import { cn } from "@/lib/utils";
import type { ContributionCalendarDay } from "@/types/openSource";

interface ContributionCalendarProps {
  year: number;
}

const COLORS = [
  "bg-zinc-200/60 dark:bg-zinc-800/60",
  "bg-emerald-300/70 dark:bg-emerald-900",
  "bg-emerald-500/80 dark:bg-emerald-700",
  "bg-emerald-500 dark:bg-emerald-500",
  "bg-emerald-600 dark:bg-emerald-400",
];

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY_LABELS = ["", "Mon", "", "Wed", "", "Fri", ""];

function intensity(count: number): number {
  if (count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  if (count <= 9) return 3;
  return 4;
}

interface Week {
  days: (ContributionCalendarDay | null)[];
  monthLabel?: string;
}

function buildWeeks(data: ContributionCalendarDay[]): Week[] {
  if (data.length === 0) return [];
  const first = new Date(data[0].date);
  const startWeekday = first.getDay();

  const cells: (ContributionCalendarDay | null)[] = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  cells.push(...data);
  while (cells.length % 7 !== 0) cells.push(null);

  const weeks: Week[] = [];
  let lastMonth = -1;
  for (let i = 0; i < cells.length; i += 7) {
    const slice = cells.slice(i, i + 7);
    const firstReal = slice.find((d) => d !== null);
    let monthLabel: string | undefined;
    if (firstReal) {
      const m = new Date(firstReal.date).getMonth();
      if (m !== lastMonth) {
        monthLabel = MONTHS[m];
        lastMonth = m;
      }
    }
    weeks.push({ days: slice, monthLabel });
  }
  return weeks;
}

export function ContributionCalendar({ year }: ContributionCalendarProps) {
  const { data, isLoading } = useOssCalendar(year);
  const weeks = useMemo(() => buildWeeks(data ?? []), [data]);

  if (isLoading) return <Skeleton className="h-32 w-full" />;

  return (
    <div className="overflow-x-auto custom-scrollbar">
      <div className="inline-flex flex-col gap-1 min-w-fit">
        <div className="flex gap-[3px] pl-7">
          {weeks.map((w, i) => (
            <div key={i} className="w-[11px] text-[10px] text-zinc-400 dark:text-zinc-500">
              {w.monthLabel ?? ""}
            </div>
          ))}
        </div>

        <div className="flex gap-2">
          <div className="flex flex-col gap-[3px] pt-[1px] text-[10px] text-zinc-400 dark:text-zinc-500">
            {DAY_LABELS.map((label, i) => (
              <div key={i} className="h-[11px] leading-[11px]">
                {label}
              </div>
            ))}
          </div>

          <div className="flex gap-[3px]">
            {weeks.map((week, wi) => (
              <div key={wi} className="flex flex-col gap-[3px]">
                {week.days.map((day, di) =>
                  day ? (
                    <div
                      key={day.date}
                      title={`${day.date}: ${day.count}`}
                      className={cn(
                        "h-[11px] w-[11px] rounded-[2px]",
                        COLORS[intensity(day.count)],
                      )}
                    />
                  ) : (
                    <div key={`empty-${wi}-${di}`} className="h-[11px] w-[11px]" />
                  ),
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export function ContributionLegend() {
  return (
    <div className="flex items-center gap-1.5 text-[11px] text-zinc-500 dark:text-zinc-400">
      <span>Less</span>
      {COLORS.map((c, i) => (
        <span key={i} className={cn("h-[10px] w-[10px] rounded-[2px]", c)} />
      ))}
      <span>More</span>
    </div>
  );
}
