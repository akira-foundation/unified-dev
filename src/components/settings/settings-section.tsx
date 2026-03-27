import type { LucideIcon } from "lucide-react";
import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";

interface SettingsSectionProps {
  title: string;
  description?: string;
  icon?: LucideIcon;
  children: React.ReactNode;
}

export function SettingsSection({ title, description, icon: Icon, children }: SettingsSectionProps) {
  return (
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
}
