import { Bell, ChevronLeft, Search } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useNavigation } from "@/hooks/useNavigation";
import { Button } from "@/components/ui/button";

export function AppHeader() {
  const { t } = useI18n();
  const { goBack, canGoBack } = useNavigation("dashboard");

  return (
    <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="flex h-14 items-center gap-4 px-4 md:px-6">
        <div className="flex flex-1 items-center gap-4 md:gap-8">
          <Button
            variant="ghost"
            size="icon"
            onClick={goBack}
            disabled={!canGoBack}
            className="shrink-0"
          >
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <div className="relative w-full max-w-[500px]">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <input
              type="search"
              placeholder={t("app.search") ?? "Search..."}
              className="h-9 w-full rounded-md border-none bg-muted/20 px-9 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button className="inline-flex h-9 w-9 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground">
            <Bell className="h-4 w-4" />
          </button>
          <div className="h-8 w-8 rounded-full bg-primary/10 flex items-center justify-center border border-primary/20">
            <span className="text-xs font-medium text-primary">UD</span>
          </div>
        </div>
      </div>
    </header>
  );
}
