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
        "flex shrink-0 flex-col gap-2 border-none bg-transparent pt-1 pb-3 md:flex-row md:items-center md:justify-end",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function PageHeaderTitle({ children, className }: { children: ReactNode; className?: string }) {
  return <h2 className={cn("sr-only", className)}>{children}</h2>;
}

export function PageHeaderMeta({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("sr-only", className)}>{children}</div>;
}

export function PageHeaderSubtitle({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("sr-only", className)}>{children}</div>;
}

export function PageHeaderActions({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("flex items-center gap-2", className)}>{children}</div>;
}
