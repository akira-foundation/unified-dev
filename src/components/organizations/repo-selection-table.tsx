import type { ProviderRepo } from "../../types/organization";
import { Checkbox } from "../ui/checkbox";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "../ui/table";
import { RepoSelectionRow } from "./repo-selection-row";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
import { useI18n } from "../../i18n/i18n";

interface RepoSelectionTableProps {
  repos: ProviderRepo[];
  selectedKeys: Set<string>;
  selectAllState: boolean | "indeterminate";
  onSelectAll: () => void;
  onClearAll: () => void;
  onToggleRepo: (repo: ProviderRepo) => void;
  onImportSelected?: () => void;
  className?: string;
}

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

export function RepoSelectionTable({
  repos,
  selectedKeys,
  selectAllState,
  onSelectAll,
  onClearAll,
  onToggleRepo,
  onImportSelected,
  className,
}: RepoSelectionTableProps) {
  const { t } = useI18n();
  return (
    <div className={`overflow-hidden rounded-xl ${className ?? ""}`}>
      <Card className="h-full flex flex-col">
        <CardHeader>
          <div className="flex items-center justify-between gap-2">
            <span className="text-sm font-semibold">{t("common.repositories")}</span>
            <Button size="sm" disabled={selectedKeys.size === 0} onClick={onImportSelected}>
              {t("common.importSelected")}
            </Button>
          </div>
        </CardHeader>
        <CardContent className="flex-1 overflow-y-auto">
          <Table className="border-separate border-spacing-y-2">
            <TableHeader className="[&_tr]:border-b-0">
              <TableRow>
                <TableHead className="w-12 rounded-l-lg bg-muted/10">
                  <Checkbox
                    checked={selectAllState}
                    onCheckedChange={(checked) => (checked ? onSelectAll() : onClearAll())}
                  />
                </TableHead>
                <TableHead className="bg-muted/10">{t("tables.header.name")}</TableHead>
                <TableHead className="rounded-r-lg bg-muted/10 text-right">{t("tables.header.visibility")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className="[&_tr]:border-b-0">
              {repos.map((repo) => (
                <RepoSelectionRow
                  key={repoKey(repo)}
                  repo={repo}
                  isSelected={selectedKeys.has(repoKey(repo))}
                  onToggle={onToggleRepo}
                />
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
