import type { ElementType } from "react";

import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

interface StatCardProps {
  label: string;
  value: number;
  sub?: string;
  icon: ElementType;
  color: string;
  bg: string;
  loading?: boolean;
  onClick?: () => void;
}

export function StatCard({ label, value, sub, icon: Icon, color, bg, loading = false, onClick }: StatCardProps) {
  return (
    <button
      onClick={onClick}
      className={cn("w-full rounded-xl text-left", onClick && "group cursor-pointer")}
    >
      <Card className="h-full">
        <CardContent className="pointer-events-none flex items-center gap-3 p-3">
          <div className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-md border border-zinc-100 dark:border-zinc-800", bg, color)}>
            <Icon size={15} />
          </div>
          <div className="min-w-0 flex-1">
            {loading ? (
              <Skeleton className="h-5 w-16" />
            ) : (
              <div className="flex items-baseline gap-1.5">
                <span className="truncate text-xl font-semibold leading-none tracking-tight text-zinc-900 dark:text-white">
                  {value}
                </span>
                {sub && <span className="truncate text-[10px] font-medium text-zinc-400 dark:text-zinc-500">{sub}</span>}
              </div>
            )}
            <div className="mt-1 truncate text-[10px] font-semibold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
              {label}
            </div>
          </div>
        </CardContent>
      </Card>
    </button>
  );
}
