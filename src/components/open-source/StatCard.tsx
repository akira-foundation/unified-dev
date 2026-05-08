import type { LucideIcon } from "lucide-react";

import { Card, CardContent, CardDescription, CardHeader } from "@/components/ui/card";
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
      className={cn("text-left w-full rounded-xl", onClick && "cursor-pointer group")}
    >
      <Card
        className={cn(
          "h-full transition-colors",
          onClick && "group-hover:border-zinc-600 group-hover:bg-zinc-900/60",
        )}
      >
        <CardHeader className="flex flex-row items-center justify-between p-5 pb-3 pointer-events-none">
          <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
            {label}
          </CardDescription>
          <div
            className={cn(
              "h-8 w-8 rounded-md flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm",
              bg,
              color,
            )}
          >
            <Icon size={16} />
          </div>
        </CardHeader>
        <CardContent className="flex justify-between items-end p-4 pt-4 gap-1.5 border-zinc-100 dark:border-zinc-800/80 bg-zinc-50/30 dark:bg-white/[0.02]">
          {loading ? (
            <Skeleton className="h-8 w-12" />
          ) : (
            <div className="text-3xl font-black tracking-tight text-zinc-900 dark:text-white leading-none truncate">
              {value}
            </div>
          )}
          <div className="text-[10px] font-semibold text-zinc-400 dark:text-zinc-500 uppercase tracking-widest pb-0.5 truncate">
            {sub}
          </div>
        </CardContent>
      </Card>
    </button>
  );
}
