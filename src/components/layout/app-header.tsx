import { Bell, ChevronLeft } from "lucide-react";
import { useNavigation } from "@/hooks/useNavigation";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { appVersion } from "@/lib/app-meta";

export function AppHeader() {
  const { goBack, canGoBack } = useNavigation("dashboard");
  const { t } = useI18n();

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="flex h-14 items-center justify-between px-4 md:px-6">
        <div className="flex items-center gap-3">
          <Button
            variant="ghost"
            size="icon"
            onClick={goBack}
            disabled={!canGoBack}
            className="shrink-0"
          >
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <div className="flex flex-col">
            <span className="text-sm font-bold tracking-tight text-foreground leading-none">{t("app.name")}</span>
            <span className="text-[10px] text-muted-foreground leading-none mt-0.5">v{appVersion}</span>
          </div>
        </div>

        <button className="inline-flex h-9 w-9 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground">
          <Bell className="h-4 w-4" />
        </button>
      </div>
    </header>
  );
}
