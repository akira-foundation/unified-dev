import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

interface PageLayoutProps {
  children: ReactNode;
  className?: string;
  scroll?: boolean;
}

export function PageLayout({ children, className, scroll = false }: PageLayoutProps) {
  return (
    <div
      className={cn(
        "flex min-h-full flex-1 flex-col space-y-4 p-4 md:p-8",
        scroll && "h-[calc(100vh-4rem)] overflow-y-auto custom-scrollbar",
        className,
      )}
    >
      {children}
    </div>
  );
}
