import { Switch } from "@/components/ui/switch";

interface FilterPopoverHeaderProps {
  title: string;
  clearLabel: string;
  canClear: boolean;
  onClear: () => void;
}

export function FilterPopoverHeader({
  title,
  clearLabel,
  canClear,
  onClear,
}: FilterPopoverHeaderProps) {
  return (
    <div className="flex items-center justify-between px-3 py-2">
      <span className="text-sm font-semibold">{title}</span>
      {canClear && (
        <button
          type="button"
          onClick={onClear}
          className="text-xs text-zinc-400 hover:text-zinc-200"
        >
          {clearLabel}
        </button>
      )}
    </div>
  );
}

export function FilterSectionDivider() {
  return <div className="border-t border-border" />;
}

interface FilterToggleOption {
  key: string;
  label: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}

interface FilterToggleSectionProps {
  label: string;
  options: FilterToggleOption[];
}

export function FilterToggleSection({ label, options }: FilterToggleSectionProps) {
  return (
    <div className="px-3 py-2 space-y-2">
      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
        {label}
      </p>
      {options.map((option) => (
        <div key={option.key} className="flex items-center justify-between">
          <span className="text-sm capitalize">{option.label}</span>
          <Switch checked={option.checked} onCheckedChange={option.onCheckedChange} />
        </div>
      ))}
    </div>
  );
}

interface FilterBooleanSectionProps {
  label: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}

export function FilterBooleanSection({
  label,
  checked,
  onCheckedChange,
}: FilterBooleanSectionProps) {
  return (
    <div className="px-3 py-2 space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-sm">{label}</span>
        <Switch checked={checked} onCheckedChange={onCheckedChange} />
      </div>
    </div>
  );
}
