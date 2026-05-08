import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useI18n } from "@/i18n/i18n";

interface OssOrgFilterProps {
  value: string;
  onChange: (value: string) => void;
  orgs: string[];
}

export function OssOrgFilter({ value, onChange, orgs }: OssOrgFilterProps) {
  const { t } = useI18n();
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="h-9 w-48 text-sm [&>span]:truncate [&>span]:block [&>span]:max-w-[150px]">
        <SelectValue placeholder={t("openSource.filters.org")} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{t("openSource.filters.allOrgs")}</SelectItem>
        {orgs.map((org) => (
          <SelectItem key={org} value={org}>
            @{org}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
