import { TriangleAlert } from "lucide-react";

interface EmptyStateProps {
  title: string;
  description?: string;
}

export function EmptyState({ title, description }: EmptyStateProps) {
  return (
    <div className="flex min-h-[60vh] w-full flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
      <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
        <TriangleAlert className="h-5 w-5" />
      </div>
      <div className="flex flex-col gap-1.5">
        <span className="text-sm font-semibold text-gray-900 dark:text-white">{title}</span>
        {description && <span className="text-[13px] text-gray-500 dark:text-gray-400">{description}</span>}
      </div>
    </div>
  );
}
