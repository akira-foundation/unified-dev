import { Tabs, TabsList, TabsTrigger } from "../ui/tabs";

interface VisibilityFilterProps {
  value: "all" | "public" | "private";
  onChange: (value: "all" | "public" | "private") => void;
}

export function VisibilityFilter({ value, onChange }: VisibilityFilterProps) {
  return (
    <Tabs value={value} onValueChange={(next) => onChange(next as "all" | "public" | "private")}>
      <TabsList>
        <TabsTrigger value="all">All</TabsTrigger>
        <TabsTrigger value="public">Public</TabsTrigger>
        <TabsTrigger value="private">Private</TabsTrigger>
      </TabsList>
    </Tabs>
  );
}
