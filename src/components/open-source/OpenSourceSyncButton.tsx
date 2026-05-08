import { Loader2, RefreshCw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { useOssSync } from "@/hooks/useOpenSource";

export function OpenSourceSyncButton() {
  const { t } = useI18n();
  const sync = useOssSync();

  return (
    <Button
      onClick={() => sync.mutate()}
      disabled={sync.isPending}
      variant="outline"
      size="sm"
    >
      {sync.isPending ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <RefreshCw className="h-4 w-4" />
      )}
      {sync.isPending ? t("openSource.sync.inProgress") : t("openSource.sync.now")}
    </Button>
  );
}
