import { useState, useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { ArrowLeft, Github, Blocks, AlertTriangle, ExternalLink, KeyRound, GitlabIcon } from "lucide-react";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";

import { cn } from "@/lib/utils";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle } from "@/components/layout/page-header";
import { Card, CardContent, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useNavigation } from "@/hooks/useNavigation";
import { useProviders } from "@/hooks/useProviders";
import { providerService } from "@/services/providerService";
import { TOKEN_META } from "@/components/providers/add-provider-dialog";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { useBrowserHandoffToast } from "@/hooks/use-browser-handoff-toast";

const tokenSchema = z.object({
  token: z.string().trim().min(10),
});

const KIND_ICON = {
  github: Github,
  gitlab: GitlabIcon,
  bitbucket: Blocks,
} as const;

const KIND_LABEL: Record<string, string> = {
  github: "GitHub",
  gitlab: "GitLab",
  bitbucket: "Bitbucket",
};

function SettingsSection({
  title,
  description,
  children,
  icon: Icon,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
  icon?: React.ComponentType<{ size?: number; strokeWidth?: number }>;
}) {
  return (
    <Card className="mb-6 overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center gap-4 px-6 py-6 pb-6">
        {Icon && (
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Icon size={22} strokeWidth={2} />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{title}</CardTitle>
          {description && <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">{description}</CardDescription>}
        </div>
      </div>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
        {children}
      </CardContent>
    </Card>
  );
}

function SettingsItem({
  label,
  description,
  action,
  className,
}: {
  label: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-3 px-6 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40", className)}>
      <div className="flex items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
          {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
        </div>
        {action && <div className="shrink-0">{action}</div>}
      </div>
    </div>
  );
}

export function ProviderDetailPage() {
  const { t } = useI18n();
  const { activeProviderId, goBack } = useNavigation("provider-detail");
  const { providers, isLoading, updateProviderAuth, removeProvider } = useProviders();
  const queryClient = useQueryClient();
  const browserHandoffToast = useBrowserHandoffToast();
  const [disconnectOpen, setDisconnectOpen] = useState(false);
  const [isDisconnecting, setIsDisconnecting] = useState(false);
  const [keepOrganizations, setKeepOrganizations] = useState(true);

  const provider = providers.find((p) => p.id === activeProviderId) ?? null;

  const form = useForm<z.infer<typeof tokenSchema>>({
    // @ts-expect-error - version mismatch between zod and hook-form resolver
    resolver: zodResolver(tokenSchema),
    mode: "onChange",
    defaultValues: { token: "" },
  });

  useEffect(() => {
    if (!isLoading && !provider) {
      goBack();
    }
  }, [isLoading, provider, goBack]);

  if (isLoading || !provider) {
    return null;
  }

  const kindLabel = KIND_LABEL[provider.kind] ?? provider.kind;
  const KindIcon = KIND_ICON[provider.kind as keyof typeof KIND_ICON] ?? Blocks;
  const meta = TOKEN_META[provider.kind] ?? TOKEN_META.github;

  const handleUpdateToken = form.handleSubmit(async (values) => {
    const toastId = toast.loading(t("pages.providerDetail.toast.updatingToken"));
    try {
      await updateProviderAuth({ providerId: provider.id, token: values.token.trim() });
      toast.success(t("pages.providerDetail.toast.tokenUpdated"), { id: toastId });
      form.reset();
    } catch (error) {
      const message = typeof error === "string" ? error : error instanceof Error ? error.message : t("pages.providerDetail.toast.tokenUpdateFailed");
      toast.error(message, { id: toastId });
    }
  });

  const handleDisconnect = async () => {
    setIsDisconnecting(true);
    const toastId = toast.loading(t("pages.providerDetail.toast.disconnecting"));
    try {
      await removeProvider(provider.id, keepOrganizations);
      toast.success(t("pages.providerDetail.toast.disconnected"), { id: toastId });
      setDisconnectOpen(false);
      goBack();
    } catch (error) {
      const message = typeof error === "string" ? error : error instanceof Error ? error.message : t("pages.providerDetail.toast.disconnectFailed");
      toast.error(message, { id: toastId });
    } finally {
      setIsDisconnecting(false);
    }
  };

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-3xl px-6">
        <div className="flex flex-col gap-4">
          <button
            onClick={goBack}
            className="flex items-center gap-2 text-zinc-500 hover:text-white transition-colors w-fit group"
          >
            <ArrowLeft className="h-4 w-4 transition-transform group-hover:-translate-x-1" />
            <span className="text-sm font-medium">{t("pages.providerDetail.back")}</span>
          </button>
          <div className="flex items-center gap-4">
            <div className="h-12 w-12 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
              <KindIcon size={24} strokeWidth={2} />
            </div>
            <div className="flex flex-col gap-1">
              <PageHeaderTitle className="text-3xl">{provider.name}</PageHeaderTitle>
              <div className="flex items-center gap-2">
                <Badge variant="secondary">{kindLabel}</Badge>
                <Badge variant="secondary" className="text-emerald-500 border-emerald-500/20 bg-emerald-500/10">{t("pages.providerDetail.connected")}</Badge>
              </div>
            </div>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-24 flex flex-col">
        <SettingsSection title={t("pages.providerDetail.details.title")} description={t("pages.providerDetail.details.description")} icon={KindIcon}>
          <SettingsItem label={t("pages.providerDetail.details.name")} description={provider.name} />
          <SettingsItem label={t("pages.providerDetail.details.kind")} description={kindLabel} />
          <SettingsItem label={t("pages.providerDetail.details.connectedSince")} description={new Date(provider.created_at).toLocaleDateString()} />
        </SettingsSection>

        <SettingsSection title={t("pages.providerDetail.auth.title")} description={t("pages.providerDetail.auth.description").replace("{label}", meta.label.toLowerCase()).replace("{kind}", kindLabel)} icon={KeyRound}>
          <div className="px-6 py-6">
            <Form {...form}>
              <form onSubmit={handleUpdateToken} className="flex flex-col gap-4">
                <FormField
                  control={form.control}
                  name="token"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>{meta.label}</FormLabel>
                      <FormControl>
                        <Input type="password" placeholder={meta.placeholder} {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <div className="flex justify-end">
                  <Button type="submit" disabled={!form.formState.isValid || form.formState.isSubmitting}>
                    {form.formState.isSubmitting ? t("common.saving") : t("pages.providerDetail.auth.updateToken")}
                  </Button>
                </div>
              </form>
            </Form>
          </div>
        </SettingsSection>

        {provider.kind === "github" && (
          <SettingsSection title="GitHub App" description="Install the GitHub App on more organizations to make their repositories available." icon={Github}>
            <SettingsItem
              label="Install on more organizations"
              description="Open the GitHub target chooser to add this app to another organization."
              action={
                <Button
                  variant="outline"
                  size="sm"
                  onClick={async () => {
                    const handoff = browserHandoffToast();
                    try {
                      await providerService.installGithubApp();
                      await queryClient.invalidateQueries({ queryKey: queryKeys.providerOrganizations(provider.id) });
                      await queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
                      await queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
                      handoff.success("GitHub App installation flow completed");
                    } catch (error) {
                      handoff.error(error, "Failed to open GitHub App installation");
                    }
                  }}
                >
                  <ExternalLink size={16} /> Install
                </Button>
              }
            />
          </SettingsSection>
        )}

        <SettingsSection title={t("common.dangerZone")} icon={AlertTriangle}>
          <SettingsItem
            label={t("pages.providerDetail.disconnect.label")}
            description={t("pages.providerDetail.disconnect.description")}
            action={
              <Button variant="destructive" size="sm" onClick={() => setDisconnectOpen(true)}>
                {t("common.disconnect")}
              </Button>
            }
          />
        </SettingsSection>
      </div>

      <AlertDialog open={disconnectOpen} onOpenChange={setDisconnectOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("pages.providerDetail.disconnect.alert.title").replace("{kind}", kindLabel)}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("pages.providerDetail.disconnect.alert.description").replace("{name}", provider.name)}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="flex items-center gap-3 py-2 px-1">
            <Switch
              id="keep-orgs"
              checked={keepOrganizations}
              onCheckedChange={setKeepOrganizations}
            />
            <label htmlFor="keep-orgs" className="text-sm">
              {t("pages.providerDetail.disconnect.alert.keepOrganizations")}
            </label>
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDisconnecting}>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={handleDisconnect} disabled={isDisconnecting}>
              {isDisconnecting ? t("pages.providerDetail.disconnect.alert.confirming") : t("pages.providerDetail.disconnect.alert.confirm")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </PageLayout>
  );
}
