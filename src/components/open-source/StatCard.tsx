import type { LucideIcon } from "lucide-react";

import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

interface StatCardProps {
  label: string;
  value: string | number;
  sub: string;
  icon: LucideIcon;
  color: string;
  bg: string;
  loading?: boolean;
  onClick?: () => void;
}

export function StatCard({
  label,
  value,
  sub,
  icon: Icon,
  color,
  bg,
  loading = false,
  onClick,
}: StatCardProps) {
  return (
    <button
      onClick={onClick}
      className={cn("text-left w-full rounded-lg", onClick && "cursor-pointer group")}
    >
      <Card className="h-full">
        <CardContent className="flex items-center gap-3 p-3 pointer-events-none">
          <div
            className={cn(
              "h-8 w-8 shrink-0 rounded-md flex items-center justify-center border border-zinc-100 dark:border-zinc-800",
              bg,
              color,
            )}
          >
            <Icon size={15} />
          </div>
          <div className="min-w-0 flex-1">
            {loading ? (
              <Skeleton className="h-5 w-16" />
            ) : (
              <div className="flex items-baseline gap-1.5">
                <span className="text-xl font-semibold tracking-tight leading-none text-zinc-900 dark:text-white truncate">
                  {value}
                </span>
                <span className="text-[10px] font-medium text-zinc-400 dark:text-zinc-500 truncate">
                  {sub}
                </span>
              </div>
            )}
            <div className="mt-1 text-[10px] font-semibold uppercase tracking-widest text-zinc-400 dark:text-zinc-500 truncate">
              {label}
            </div>
          </div>
        </CardContent>
      </Card>
    </button>
  );
}
