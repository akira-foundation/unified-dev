import { TimerReset } from "lucide-react";

import { Card, CardContent } from "@/components/ui/card";
import { useI18n } from "@/i18n/i18n";

export function GithubRateLimitedState() {
  const { t } = useI18n();

  return (
    <Card>
      <CardContent className="flex flex-col items-center justify-center gap-4 p-10 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
          <TimerReset className="h-6 w-6" />
        </div>
        <div className="flex flex-col gap-1">
          <span className="text-base font-semibold">{t("openSource.rateLimited.title")}</span>
          <span className="max-w-md text-sm text-zinc-500 dark:text-zinc-400">
            {t("openSource.rateLimited.description")}
          </span>
        </div>
      </CardContent>
    </Card>
  );
}
