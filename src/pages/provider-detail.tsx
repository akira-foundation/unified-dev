import { useState, useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { ArrowLeft, Github, Blocks, AlertTriangle, KeyRound, GitlabIcon } from "lucide-react";
import { toast } from "sonner";

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
import { useNavigation } from "@/hooks/useNavigation";
import { useProviders } from "@/hooks/useProviders";
import { TOKEN_META } from "@/components/providers/add-provider-dialog";

const tokenSchema = z.object({
  token: z.string().trim().min(10, "Token is required"),
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
  const { activeProviderId, goBack } = useNavigation("provider-detail");
  const { providers, isLoading, updateProviderAuth, removeProvider } = useProviders();
  const [disconnectOpen, setDisconnectOpen] = useState(false);
  const [isDisconnecting, setIsDisconnecting] = useState(false);

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
    const toastId = toast.loading("Atualizando token...");
    try {
      await updateProviderAuth({ providerId: provider.id, token: values.token.trim() });
      toast.success("Token atualizado", { id: toastId });
      form.reset();
    } catch (error) {
      const message = typeof error === "string" ? error : error instanceof Error ? error.message : "Falha ao atualizar token";
      toast.error(message, { id: toastId });
    }
  });

  const handleDisconnect = async () => {
    setIsDisconnecting(true);
    const toastId = toast.loading("Desconectando...");
    try {
      await removeProvider(provider.id);
      toast.success("Provider desconectado", { id: toastId });
      setDisconnectOpen(false);
      goBack();
    } catch (error) {
      const message = typeof error === "string" ? error : error instanceof Error ? error.message : "Falha ao desconectar";
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
            <span className="text-sm font-medium">Back</span>
          </button>
          <div className="flex items-center gap-4">
            <div className="h-12 w-12 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
              <KindIcon size={24} strokeWidth={2} />
            </div>
            <div className="flex flex-col gap-1">
              <PageHeaderTitle className="text-3xl">{provider.name}</PageHeaderTitle>
              <div className="flex items-center gap-2">
                <Badge variant="secondary">{kindLabel}</Badge>
                <Badge variant="secondary" className="text-emerald-500 border-emerald-500/20 bg-emerald-500/10">Connected</Badge>
              </div>
            </div>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-24 flex flex-col">
        <SettingsSection title="Details" description="Provider information." icon={KindIcon}>
          <SettingsItem label="Name" description={provider.name} />
          <SettingsItem label="Kind" description={kindLabel} />
          <SettingsItem label="Connected since" description={new Date(provider.created_at).toLocaleDateString()} />
        </SettingsSection>

        <SettingsSection title="Authentication" description={`Update the ${meta.label.toLowerCase()} used to authenticate with ${kindLabel}.`} icon={KeyRound}>
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
                    {form.formState.isSubmitting ? "Saving..." : "Update token"}
                  </Button>
                </div>
              </form>
            </Form>
          </div>
        </SettingsSection>

        <SettingsSection title="Danger Zone" icon={AlertTriangle}>
          <SettingsItem
            label="Disconnect provider"
            description="Remove this provider and all linked organizations permanently. This action cannot be undone."
            action={
              <Button variant="destructive" size="sm" onClick={() => setDisconnectOpen(true)}>
                Disconnect
              </Button>
            }
          />
        </SettingsSection>
      </div>

      <AlertDialog open={disconnectOpen} onOpenChange={setDisconnectOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Disconnect {kindLabel}?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently remove <strong>{provider.name}</strong> and all organizations linked to it. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDisconnecting}>Cancel</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={handleDisconnect} disabled={isDisconnecting}>
              {isDisconnecting ? "Disconnecting..." : "Yes, disconnect"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </PageLayout>
  );
}
