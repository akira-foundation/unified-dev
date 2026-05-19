import { Github, Loader2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { useI18n } from "@/i18n/i18n";

interface Props {
  onReconnect?: () => Promise<void>;
}

export function GithubAppNoUserTokenState({ onReconnect }: Props) {
  const { t } = useI18n();
  const [isPending, setIsPending] = useState(false);

  async function handleReconnect() {
    if (!onReconnect) return;
    setIsPending(true);
    try {
      await onReconnect();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      toast.error(message);
    } finally {
      setIsPending(false);
    }
  }

  return (
    <Card>
      <CardContent className="flex flex-col items-center justify-center gap-4 p-12 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-zinc-900/5 text-zinc-700 dark:bg-zinc-50/10 dark:text-zinc-200">
          <Github className="h-6 w-6" />
        </div>
        <div className="flex flex-col gap-1">
          <span className="text-base font-semibold">{t("openSource.appNoUserToken.title")}</span>
          <span className="max-w-md text-sm text-zinc-500 dark:text-zinc-400">
            {t("openSource.appNoUserToken.description")}
          </span>
        </div>
        {onReconnect && (
          <Button onClick={handleReconnect} disabled={isPending}>
            {isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            {t("common.reconnect")}
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
