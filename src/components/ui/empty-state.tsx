import { TriangleAlert } from "lucide-react";
import { Card, CardContent } from "./card";
import { Skeleton } from "./skeleton";

interface EmptyStateProps {
  title: string;
  description: string;
}

export function EmptyState({ title, description }: EmptyStateProps) {
  return (
    <Card>
      <CardContent className="relative flex flex-col items-center justify-center gap-6 p-10 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
          <TriangleAlert className="h-6 w-6" />
        </div>
        <div className="flex flex-col gap-2">
          <span className="text-base font-semibold text-gray-900 dark:text-white">{title}</span>
          <span className="text-sm text-gray-500 dark:text-gray-400">{description}</span>
        </div>
        <div className="w-full max-w-2xl space-y-3 opacity-60">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-[90%]" />
          <Skeleton className="h-10 w-[85%]" />
          <Skeleton className="h-10 w-[80%]" />
        </div>
      </CardContent>
    </Card>
  );
}
