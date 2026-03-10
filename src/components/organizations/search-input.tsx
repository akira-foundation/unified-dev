import { Search } from "lucide-react";

import { Input } from "../ui/input";

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}

export function SearchInput({ value, onChange, placeholder }: SearchInputProps) {
  return (
    <div className="relative">
      <Search className="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
      <Input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder ?? "Search repositories"}
        className="h-9 border border-zinc-200 bg-white/60 pl-9 text-sm shadow-sm focus-visible:ring-2 focus-visible:ring-zinc-400/40 dark:border-zinc-800 dark:bg-zinc-950/40"
      />
    </div>
  );
}
