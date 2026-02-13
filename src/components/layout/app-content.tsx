import type { ComponentProps } from "react";

import { SidebarInset } from "@/components/ui/sidebar";

interface AppContentProps extends ComponentProps<"main"> {
  variant?: "header" | "sidebar";
}

export function AppContent({ variant = "sidebar", children, ...props }: AppContentProps) {
  if (variant === "sidebar") {
    return <SidebarInset {...props}>{children}</SidebarInset>;
  }

  return (
    <main className="mx-auto flex h-full w-full max-w-7xl flex-1 flex-col gap-4 rounded-xl" {...props}>
      {children}
    </main>
  );
}
