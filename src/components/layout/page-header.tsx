import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

interface PageHeaderProps {
  children: ReactNode;
  className?: string;
}

export function PageHeader({ children, className }: PageHeaderProps) {
  return (
    <div
      className={cn(
        "flex shrink-0 flex-col gap-4 border-none bg-transparent py-6 md:flex-row md:items-center md:justify-between",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function PageHeaderTitle({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <h2 className={cn("text-4xl font-bold tracking-tight text-foreground", className)}>
      {children}
    </h2>
  );
}

export function PageHeaderMeta({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("mt-1.5 flex items-center text-sm font-medium text-zinc-500", className)}>
      {children}
    </div>
  );
}

export function PageHeaderSubtitle({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("mt-1 text-sm text-muted-foreground", className)}>{children}</div>;
}

export function PageHeaderActions({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("flex items-center gap-4", className)}>{children}</div>;
}
