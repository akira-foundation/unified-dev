import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

import { cn } from "@/lib/utils";

interface PageHeaderProps {
  children: ReactNode;
  className?: string;
}

export function PageHeader({ children, className }: PageHeaderProps) {
  return <div className={cn("contents", className)}>{children}</div>;
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
  const anchorRef = useRef<HTMLSpanElement>(null);
  const [target, setTarget] = useState<HTMLElement | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    setTarget(document.getElementById("appbar-actions"));
    const v = anchorRef.current?.offsetParent != null;
    setVisible((prev) => (prev === v ? prev : v));
  });

  return (
    <>
      <span ref={anchorRef} aria-hidden />
      {target && visible
        ? createPortal(<div className={cn("flex items-center gap-2", className)}>{children}</div>, target)
        : null}
    </>
  );
}
