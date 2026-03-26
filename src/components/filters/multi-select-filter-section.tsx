import { X } from "lucide-react";

import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";

interface MultiSelectFilterSectionProps {
  label: string;
  placeholder: string;
  items: string[];
  value: string[];
  onValueChange: (value: string[]) => void;
}

export function MultiSelectFilterSection({
  label,
  placeholder,
  items,
  value,
  onValueChange,
}: MultiSelectFilterSectionProps) {
  return (
    <div className="px-3 py-2 space-y-1.5">
      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
        {label}
      </p>
      <Combobox items={items} multiple value={value} onValueChange={(next) => onValueChange(next as string[])}>
        <ComboboxInput placeholder={placeholder} className="w-full text-xs" showTrigger={false} />
        <ComboboxContent className="bg-card text-card-foreground">
          <ComboboxEmpty>No results.</ComboboxEmpty>
          <ComboboxList>
            {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
          </ComboboxList>
        </ComboboxContent>
      </Combobox>
      {value.length > 0 && (
        <div className="flex flex-wrap gap-1 pt-1">
          {value.map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => onValueChange(value.filter((current) => current !== item))}
              className="inline-flex items-center gap-1 rounded-[6px] bg-muted px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            >
              <span>{item}</span>
              <X className="h-3 w-3" />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
