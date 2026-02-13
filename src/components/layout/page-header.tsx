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

export function PageHeaderTitle({ children }: { children: ReactNode }) {
  return <h2 className="text-3xl font-semibold tracking-tight text-foreground">{children}</h2>;
}

export function PageHeaderMeta({ children }: { children: ReactNode }) {
  return <div className="mt-1 flex items-center text-sm text-muted-foreground">{children}</div>;
}

export function PageHeaderSubtitle({ children }: { children: ReactNode }) {
  return <div className="mt-1 text-sm text-muted-foreground">{children}</div>;
}

export function PageHeaderActions({ children }: { children: ReactNode }) {
  return <div className="flex items-center gap-3">{children}</div>;
}
