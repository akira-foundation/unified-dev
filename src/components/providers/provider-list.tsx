import type { ProviderSummary } from "../../types/provider";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { Button } from "../ui/button";
import { MoreHorizontal, Plus } from "lucide-react";

interface ProviderListProps {
  providers: ProviderSummary[];
  onRemove: (id: string) => void;
  onCreate?: () => void;
}

const kindLabel = (kind: string) => {
  switch (kind) {
    case "github":
      return "GitHub";
    case "gitlab":
      return "GitLab";
    case "bitbucket":
      return "Bitbucket";
    default:
      return kind;
  }
};

export function ProviderList({ providers, onRemove, onCreate }: ProviderListProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle>Providers</CardTitle>
          <CardDescription>Reusable VCS connections used by organizations.</CardDescription>
        </div>
        {onCreate && (
          <Button variant="outline" size="sm" onClick={onCreate} className="gap-2">
            <Plus className="h-4 w-4" />
            New Provider
          </Button>
        )}
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {providers.length === 0 ? (
          <div className="rounded-xl  px-4 py-6 text-sm text-gray-500  dark:text-gray-400">
            No providers configured yet.
          </div>
        ) : (
          providers.map((provider) => (
            <div
              key={provider.id}
              className="flex items-center justify-between rounded-xl bg-white px-4 py-3 shadow-sm dark:bg-gray-900"
            >
              <div className="flex flex-col gap-1">
                <div className="text-sm font-semibold text-gray-900 dark:text-white">{provider.name}</div>
                <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                  <Badge variant="secondary">{kindLabel(provider.kind)}</Badge>
                  <span>Created {new Date(provider.created_at).toLocaleDateString()}</span>
                </div>
              </div>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon">
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onClick={() => onRemove(provider.id)} className="text-red-500">
                    Remove provider
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}
