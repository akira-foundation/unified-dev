import { Tabs, TabsList, TabsTrigger } from "../ui/tabs";
import { useI18n } from "../../i18n/i18n";

interface VisibilityFilterProps {
  value: "all" | "public" | "private";
  onChange: (value: "all" | "public" | "private") => void;
}

export function VisibilityFilter({ value, onChange }: VisibilityFilterProps) {
  const { t } = useI18n();
  return (
    <Tabs value={value} onValueChange={(next) => onChange(next as "all" | "public" | "private")}>
      <TabsList className="h-auto gap-1 rounded-full border border-zinc-200 bg-zinc-100/50 dark:border-zinc-800/50 dark:bg-zinc-900/50">
        <TabsTrigger
          value="all"
          className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm data-[state=active]:border-zinc-200 dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white dark:data-[state=active]:border-transparent border border-transparent"
        >
          {t("filters.visibility.all")}
        </TabsTrigger>
        <TabsTrigger
          value="public"
          className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm data-[state=active]:border-zinc-200 dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white dark:data-[state=active]:border-transparent border border-transparent"
        >
          {t("filters.visibility.public")}
        </TabsTrigger>
        <TabsTrigger
          value="private"
          className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm data-[state=active]:border-zinc-200 dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white dark:data-[state=active]:border-transparent border border-transparent"
        >
          {t("filters.visibility.private")}
        </TabsTrigger>
      </TabsList>
    </Tabs>
  );
}
