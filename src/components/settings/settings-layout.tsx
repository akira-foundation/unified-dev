import { useMemo } from "react";
import type { ReactNode } from "react";

import { Heading } from "@/components/heading";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

interface SettingsNavItem {
  id: string;
  title: string;
}

interface SettingsLayoutProps {
  children: ReactNode;
  activeId: string;
  onSelect: (id: string) => void;
  navItems?: SettingsNavItem[];
}

const defaultNavItems: SettingsNavItem[] = [
  { id: "profile", title: "Profile" },
  { id: "password", title: "Password" },
  { id: "two-factor", title: "Two-Factor Auth" },
  { id: "appearance", title: "Appearance" },
];

export function SettingsLayout({ children, activeId, onSelect, navItems }: SettingsLayoutProps) {
  const items = useMemo(() => navItems ?? defaultNavItems, [navItems]);

  return (
    <div className="px-4 py-6">
      <Heading title="Settings" description="Manage your profile and account settings" />

      <div className="flex flex-col lg:flex-row lg:space-x-12">
        <aside className="w-full max-w-xl lg:w-48">
          <nav className="flex flex-col space-y-1 space-x-0">
            {items.map((item) => (
              <Button
                key={item.id}
                size="sm"
                variant="ghost"
                className={cn("w-full justify-start", {
                  "bg-muted": activeId === item.id,
                })}
                onClick={() => onSelect(item.id)}
              >
                {item.title}
              </Button>
            ))}
          </nav>
        </aside>

        <Separator className="my-6 lg:hidden" />

        <div className="flex-1 md:max-w-2xl">
          <section className="max-w-xl space-y-12">{children}</section>
        </div>
      </div>
    </div>
  );
}
