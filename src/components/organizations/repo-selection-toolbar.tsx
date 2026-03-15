import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { SearchInput } from "./search-input";
import { VisibilityFilter } from "./visibility-filter";
import { useI18n } from "../../i18n/i18n";

interface RepoSelectionToolbarProps {
  search: string;
  visibility: "all" | "public" | "private";
  selectedCount: number;
  isSaving: boolean;
  onSearchChange: (value: string) => void;
  onVisibilityChange: (value: "all" | "public" | "private") => void;
  onSave: () => void;
  onSync: () => void;
}

export function RepoSelectionToolbar({
  search,
  visibility,
  selectedCount,
  isSaving,
  onSearchChange,
  onVisibilityChange,
  onSave,
  onSync,
}: RepoSelectionToolbarProps) {
  const { t } = useI18n();
  return (
    <Card>
      <CardContent className="flex flex-col gap-4 p-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-1 flex-col gap-3 lg:flex-row lg:items-center">
          <div className="w-full lg:max-w-xs">
            <SearchInput value={search} onChange={onSearchChange} />
          </div>
          <VisibilityFilter value={visibility} onChange={onVisibilityChange} />
        </div>
        <div className="flex flex-col gap-3 text-sm text-gray-500 dark:text-gray-400 lg:flex-row lg:items-center">
          <span>{t("toolbar.repositories.selected").replace("{count}", String(selectedCount))}</span>
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={onSync} disabled={selectedCount === 0 || isSaving}>
              {t("common.syncNow")}
            </Button>
            <Button onClick={onSave} disabled={isSaving}>
              {isSaving ? t("common.saving") : t("toolbar.saveSelection")}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
