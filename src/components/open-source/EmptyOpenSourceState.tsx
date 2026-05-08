import { EmptyState } from "@/components/ui/empty-state";
import { useI18n } from "@/i18n/i18n";

export function EmptyOpenSourceState() {
  const { t } = useI18n();
  return (
    <EmptyState
      title={t("openSource.empty.title")}
      description={t("openSource.empty.description")}
    />
  );
}
