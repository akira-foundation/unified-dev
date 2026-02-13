import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { SearchInput } from "./search-input";
import { VisibilityFilter } from "./visibility-filter";

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
          <span>{selectedCount} repositories selected</span>
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={onSync} disabled={selectedCount === 0 || isSaving}>
              Sync now
            </Button>
            <Button onClick={onSave} disabled={isSaving}>
              {isSaving ? "Saving..." : "Save selection"}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
