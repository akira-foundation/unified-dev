import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { providerService } from "@/services/providerService";
import type { ProviderOrg, ProviderSummary } from "@/types/provider";
import type { OrganizationSummary } from "@/types/organization";

interface CreateRepositoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  providers: ProviderSummary[];
  organizations: OrganizationSummary[];
  defaultOrganizationId?: string;
  onCreated?: (repo: CreatedRepo) => void;
}

interface CreatedRepo {
  id: number;
  name: string;
  full_name: string;
  html_url: string;
  private: boolean;
  description: string | null;
}

export function CreateRepositoryDialog({
  open,
  onOpenChange,
  providers,
  organizations,
  defaultOrganizationId,
  onCreated,
}: CreateRepositoryDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const githubProvider = providers.find((p) => p.kind === "github");

  const [providerOrgs, setProviderOrgs] = useState<ProviderOrg[]>([]);
  const [providerOrgLogin, setProviderOrgLogin] = useState<string>("");
  const [localOrgId, setLocalOrgId] = useState<string>(defaultOrganizationId ?? "");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [visibility, setVisibility] = useState<"private" | "public">("private");
  const [isLoadingOrgs, setIsLoadingOrgs] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (defaultOrganizationId) setLocalOrgId(defaultOrganizationId);
  }, [defaultOrganizationId]);

  useEffect(() => {
    if (!open || !githubProvider) return;

    setIsLoadingOrgs(true);
    providerService
      .listProviderOrganizations(githubProvider.id)
      .then((data) => {
        setProviderOrgs(data);
        if (data.length > 0) setProviderOrgLogin(data[0].login);
      })
      .catch(() => {})
      .finally(() => setIsLoadingOrgs(false));
  }, [open, githubProvider?.id]);

  function reset() {
    setName("");
    setDescription("");
    setVisibility("private");
    setProviderOrgLogin(providerOrgs[0]?.login ?? "");
    setLocalOrgId(defaultOrganizationId ?? "");
  }

  function handleClose(value: boolean) {
    if (!value) reset();
    onOpenChange(value);
  }

  async function handleSubmit() {
    if (!githubProvider || !name.trim() || !localOrgId) return;

    const selectedOrg = providerOrgs.find((o) => o.login === providerOrgLogin);

    setIsSubmitting(true);
    try {
      const repo = await invoke<CreatedRepo>("create_provider_repository", {
        input: {
          provider_id: githubProvider.id,
          organization_login: selectedOrg?.kind === "organization" ? selectedOrg.login : null,
          name: name.trim(),
          description: description.trim() || null,
          private: visibility === "private",
        },
      });

      const [owner, repoName] = repo.full_name.split("/");
      await invoke("save_selected_repositories", {
        organizationId: localOrgId,
        repoList: [{
          owner,
          repo_name: repoName,
          visibility: repo.private ? "private" : "public",
          is_selected: true,
          auto_sync: true,
          default_branch: null,
          open_prs_count: null,
          is_fork: false,
        }],
      });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() }),
        queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(localOrgId) }),
      ]);

      toast.success(t("dialogs.createRepository.success").replace("{name}", repo.full_name));
      onCreated?.(repo);
      handleClose(false);
    } catch (err) {
      const msg = String(err);
      const clean = msg.startsWith("provider error: ") ? msg.slice("provider error: ".length) : msg;
      toast.error(clean);
    } finally {
      setIsSubmitting(false);
    }
  }

  const canSubmit = !isSubmitting && !isLoadingOrgs && name.trim().length > 0 && !!localOrgId;

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("dialogs.createRepository.title")}</DialogTitle>
          <DialogDescription>{t("dialogs.createRepository.description")}</DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-5 py-4 border-t border-border/50">
          <div className="flex flex-col gap-2">
            <Label className="text-sm font-medium">{t("dialogs.createRepository.localOrg")}</Label>
            <Select value={localOrgId} onValueChange={setLocalOrgId}>
              <SelectTrigger>
                <SelectValue placeholder={t("dialogs.createRepository.localOrgPlaceholder")} />
              </SelectTrigger>
              <SelectContent>
                {organizations.map((org) => (
                  <SelectItem key={org.id} value={org.id}>
                    {org.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-2">
            <Label className="text-sm font-medium">{t("dialogs.createRepository.owner")}</Label>
            {isLoadingOrgs ? (
              <div className="h-9 rounded-md border border-input bg-muted animate-pulse" />
            ) : (
              <Select value={providerOrgLogin} onValueChange={setProviderOrgLogin}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {providerOrgs.map((org) => (
                    <SelectItem key={org.login} value={org.login}>
                      {org.login}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </div>

          <div className="h-px bg-border/50" />

          <div className="flex flex-col gap-2">
            <Label htmlFor="repo-name" className="text-sm font-medium">{t("dialogs.createRepository.name")}</Label>
            <Input
              id="repo-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("dialogs.createRepository.namePlaceholder")}
              autoFocus
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="repo-description" className="text-sm font-medium">
              {t("dialogs.createRepository.descriptionLabel")}
              <span className="ml-1.5 text-xs font-normal text-muted-foreground">({t("common.optional")})</span>
            </Label>
            <Textarea
              id="repo-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t("dialogs.createRepository.descriptionPlaceholder")}
              rows={2}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label className="text-sm font-medium">{t("dialogs.createRepository.visibility")}</Label>
            <Select value={visibility} onValueChange={(v) => setVisibility(v as "private" | "public")}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="private">{t("dialogs.createRepository.private")}</SelectItem>
                <SelectItem value="public">{t("dialogs.createRepository.public")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter className="border-t border-border/50 pt-4">
          <Button variant="ghost" onClick={() => handleClose(false)} disabled={isSubmitting}>
            {t("common.cancel")}
          </Button>
          <Button onClick={handleSubmit} disabled={!canSubmit}>
            {isSubmitting ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t("dialogs.createRepository.creating")}
              </span>
            ) : (
              t("dialogs.createRepository.create")
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
