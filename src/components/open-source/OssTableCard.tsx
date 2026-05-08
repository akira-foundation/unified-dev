import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

import { Card, CardContent } from "@/components/ui/card";

interface OssTableCardProps {
  icon: LucideIcon;
  title: string;
  count: number | string;
  actions?: ReactNode;
  children: ReactNode;
}

export function OssTableCard({ icon: Icon, title, count, actions, children }: OssTableCardProps) {
  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-4 px-6 py-6">
        <div className="flex flex-row items-center gap-4 min-w-0">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Icon size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1 min-w-0">
            <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none truncate">
              {title}
            </span>
            <span className="text-[13px] font-medium text-zinc-500/80 leading-none truncate">
              {count}
            </span>
          </div>
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </div>

      <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50 px-0">
        <div className="overflow-hidden rounded-xl">{children}</div>
      </CardContent>
    </Card>
  );
}
