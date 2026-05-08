import { Search } from "lucide-react";

import { Input } from "@/components/ui/input";

interface OssTableSearchProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}

export function OssTableSearch({ value, onChange, placeholder }: OssTableSearchProps) {
  return (
    <div className="relative">
      <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-500 pointer-events-none" />
      <Input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="pl-8 h-9 w-56 text-sm focus-visible:ring-purple-500/50"
      />
    </div>
  );
}
