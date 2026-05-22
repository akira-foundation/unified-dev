import { useEffect, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

import { cn } from "@/lib/utils";

export function AppbarActions({ children, className }: { children: ReactNode; className?: string }) {
  const [target, setTarget] = useState<HTMLElement | null>(null);

  useEffect(() => {
    setTarget(document.getElementById("appbar-actions"));
  }, []);

  if (!target) return null;

  return createPortal(<div className={cn("flex items-center gap-2", className)}>{children}</div>, target);
}
