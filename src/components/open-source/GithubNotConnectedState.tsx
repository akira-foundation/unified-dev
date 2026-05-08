import { Github } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";

export function GithubNotConnectedState() {
  const { t } = useI18n();
  const navigateTo = useNavigationStore((s) => s.navigateTo);

  return (
    <Card>
      <CardContent className="flex flex-col items-center justify-center gap-4 p-12 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-zinc-900/5 text-zinc-700 dark:bg-zinc-50/10 dark:text-zinc-200">
          <Github className="h-6 w-6" />
        </div>
        <div className="flex flex-col gap-1">
          <span className="text-base font-semibold">{t("openSource.notConnected.title")}</span>
          <span className="max-w-md text-sm text-zinc-500 dark:text-zinc-400">
            {t("openSource.notConnected.description")}
          </span>
        </div>
        <Button onClick={() => navigateTo("provider-detail")}>
          {t("openSource.notConnected.cta")}
        </Button>
      </CardContent>
    </Card>
  );
}
