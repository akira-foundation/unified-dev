import { useState } from "react";

import type { ProviderSummary } from "../../types/provider";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardDescription, CardTitle } from "../ui/card";
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
import { KeyRound, MoreVertical, Plus, Trash2, Server } from "lucide-react";
import { useI18n } from "../../i18n/i18n";

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
  const { t } = useI18n();
  const [providerToRemove, setProviderToRemove] = useState<ProviderSummary | null>(null);

  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center justify-between px-6 py-6 pb-6">
        <div className="flex flex-row items-center gap-4">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Server size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1">
            <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{t("components.providerList.title")}</CardTitle>
            <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">{t("components.providerList.description")}</CardDescription>
          </div>
        </div>
        {onCreate && (
          <Button onClick={onCreate}>
            <Plus size={18} />
            {t("common.newProvider")}
          </Button>
        )}
      </div>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
        {providers.length === 0 ? (
          <div className="rounded-md  px-4 py-6 text-sm text-gray-500  dark:text-gray-400">
            {t("components.providerList.empty")}
          </div>
        ) : (
          providers.map((provider) => (
            <div
              key={provider.id}
              className="flex items-center justify-between rounded-md  px-4 py-3 shadow-sm"
            >
              <div className="flex flex-col gap-1">
                <div className="text-sm font-semibold text-gray-900 dark:text-white">{provider.name}</div>
                <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                  <Badge variant="secondary">{kindLabel(provider.kind)}</Badge>
                  <span>{t("components.providerList.created")} {new Date(provider.created_at).toLocaleDateString()}</span>
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
                      {t("common.updateToken")}
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuItem onClick={() => setProviderToRemove(provider)} className="text-red-500">
                    <Trash2 className="mr-2 h-4 w-4" />
                    {t("common.removeProvider")}
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
            <AlertDialogTitle>{t("common.removeProvider")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("components.providerList.removeDialog.description")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                if (providerToRemove) {
                  onRemove(providerToRemove.id);
                }
                setProviderToRemove(null);
              }}
            >
              {t("common.remove")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
