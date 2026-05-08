import { Filter, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useI18n } from "@/i18n/i18n";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

const YEARS = [2026, 2025, 2024, 2023, 2022, 2021, 2020];
const TYPES: Array<"pr" | "issue" | "review" | "commit"> = ["pr", "issue", "review", "commit"];
const STATES = ["open", "merged", "closed"];

export function OpenSourceFilters() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();

  const hasFilters = Boolean(
    filters.year || filters.org || filters.repo || filters.type || filters.state,
  );

  return (
    <div className="flex items-center gap-2">
      <Popover>
        <PopoverTrigger asChild>
          <Button variant="outline" size="sm">
            <Filter className="h-4 w-4" />
            {t("openSource.filters.title")}
            {hasFilters ? <span className="ml-1 h-2 w-2 rounded-full bg-purple-500" /> : null}
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-80 space-y-4 p-4">
          <div className="space-y-2">
            <Label>{t("openSource.filters.year")}</Label>
            <Select
              value={filters.year ? String(filters.year) : "all"}
              onValueChange={(value) => filters.setYear(value === "all" ? undefined : Number(value))}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("openSource.filters.allYears")}</SelectItem>
                {YEARS.map((y) => (
                  <SelectItem key={y} value={String(y)}>
                    {y}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>{t("openSource.filters.org")}</Label>
            <Input
              placeholder={t("openSource.filters.allOrgs")}
              value={filters.org ?? ""}
              onChange={(e) => filters.setOrg(e.target.value || undefined)}
            />
          </div>

          <div className="space-y-2">
            <Label>{t("openSource.filters.repo")}</Label>
            <Input
              placeholder={t("openSource.filters.allRepos")}
              value={filters.repo ?? ""}
              onChange={(e) => filters.setRepo(e.target.value || undefined)}
            />
          </div>

          <div className="space-y-2">
            <Label>{t("openSource.filters.type")}</Label>
            <Select
              value={filters.type ?? "all"}
              onValueChange={(value) =>
                filters.setType(value === "all" ? undefined : (value as typeof TYPES[number]))
              }
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">—</SelectItem>
                {TYPES.map((tt) => (
                  <SelectItem key={tt} value={tt}>
                    {tt}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>{t("openSource.filters.state")}</Label>
            <Select
              value={filters.state ?? "all"}
              onValueChange={(value) => filters.setState(value === "all" ? undefined : value)}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("openSource.filters.allStates")}</SelectItem>
                {STATES.map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </PopoverContent>
      </Popover>
      {hasFilters ? (
        <Button variant="ghost" size="sm" onClick={() => filters.reset()}>
          <X className="h-4 w-4" />
          {t("openSource.filters.clear")}
        </Button>
      ) : null}
    </div>
  );
}
