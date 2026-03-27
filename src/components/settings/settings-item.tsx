import { cn } from "@/lib/utils";

interface SettingsItemProps {
  label: string;
  description?: string;
  action?: React.ReactNode;
  destructive?: boolean;
  className?: string;
}

export function SettingsItem({ label, description, action, destructive = false, className }: SettingsItemProps) {
  return (
    <div
      className={cn(
        "flex items-center justify-between px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40",
        className,
      )}
    >
      <div className="flex flex-col gap-1 w-full max-w-[65%]">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
        {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
      </div>
      <div className={cn("shrink-0", destructive ? "text-red-600" : "text-zinc-700 dark:text-zinc-200")}>{action}</div>
    </div>
  );
}
