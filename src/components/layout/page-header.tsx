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
        " sticky top-0 z-30 -mx-4 flex shrink-0 flex-col gap-2 border-b border-zinc-800/40 bg-background/90 px-4 py-3 backdrop-blur md:-mx-8 md:flex-row md:items-center md:justify-between md:px-8",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function PageHeaderTitle({ children, className }: { children: ReactNode; className?: string }) {
  return <h2 className={cn("text-3xl font-semibold tracking-tight text-foreground", className)}>{children}</h2>;
}

export function PageHeaderMeta({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("mt-1 flex items-center text-sm text-muted-foreground", className)}>{children}</div>;
}

export function PageHeaderSubtitle({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("mt-1 text-sm text-muted-foreground", className)}>{children}</div>;
}

export function PageHeaderActions({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("flex items-center gap-3", className)}>{children}</div>;
}
