import { cn } from "@/lib/utils";

interface YearSelectorProps {
  years: number[];
  value: number;
  onChange: (year: number) => void;
}

export function YearSelector({ years, value, onChange }: YearSelectorProps) {
  return (
    <div className="flex w-32 shrink-0 flex-col gap-1">
      {years.map((year) => (
        <button
          key={year}
          onClick={() => onChange(year)}
          className={cn(
            "w-full rounded-md px-3 py-1.5 text-left text-xs font-semibold transition-colors",
            year === value
              ? "bg-purple-600 text-white"
              : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800/60",
          )}
        >
          {year}
        </button>
      ))}
    </div>
  );
}
