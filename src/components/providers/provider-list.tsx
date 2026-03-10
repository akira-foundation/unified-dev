import { useState } from "react";

import type { ProviderSummary } from "../../types/provider";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../ui/alert-dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { KeyRound, MoreVertical, Plus, Trash2 } from "lucide-react";

interface ProviderListProps {
  providers: ProviderSummary[];
  onRemove: (id: string) => void;
  onUpdateToken?: (provider: ProviderSummary) => void;
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

export function ProviderList({ providers, onRemove, onCreate, onUpdateToken }: ProviderListProps) {
  const [providerToRemove, setProviderToRemove] = useState<ProviderSummary | null>(null);

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
              className="flex items-center justify-between rounded-xl  px-4 py-3 shadow-sm"
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
                    <MoreVertical className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  {onUpdateToken && (
                    <DropdownMenuItem onClick={() => onUpdateToken(provider)}>
                      <KeyRound className="mr-2 h-4 w-4" />
                      Update token
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuItem onClick={() => setProviderToRemove(provider)} className="text-red-500">
                    <Trash2 className="mr-2 h-4 w-4" />
                    Remove provider
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          ))
        )}
      </CardContent>
      <AlertDialog open={Boolean(providerToRemove)} onOpenChange={(open) => (!open ? setProviderToRemove(null) : null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove provider</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete the provider configuration and disconnect any linked organizations.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                if (providerToRemove) {
                  onRemove(providerToRemove.id);
                }
                setProviderToRemove(null);
              }}
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
