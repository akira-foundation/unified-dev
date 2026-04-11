import { useState } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { invoke } from "@tauri-apps/api/core";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useUpgradeModalStore, type FreeTierLimitType } from "@/stores/upgrade-modal-store";
import { useI18n } from "@/i18n/i18n";
import { useCheckoutPoller } from "@/hooks/useCheckoutPoller";
import { useLicenseStore } from "@/stores/license-store";

interface CheckoutDto {
  url: string;
  sessionId: string;
}

const LIMIT_CONFIG: Record<FreeTierLimitType, {
    titleKey: string;
    descriptionKey: string;
    targetPlan: "pro" | "ultimate";
}> = {
    run_limit_reached: {
        titleKey: "upgrade.limit.runs.title",
        descriptionKey: "upgrade.limit.runs.description",
        targetPlan: "pro",
    },
    thread_limit_reached: {
        titleKey: "upgrade.limit.threads.title",
        descriptionKey: "upgrade.limit.threads.description",
        targetPlan: "pro",
    },
    repo_limit_reached: {
        titleKey: "upgrade.limit.repos.title",
        descriptionKey: "upgrade.limit.repos.description",
        targetPlan: "pro",
    },
    org_limit_reached: {
        titleKey: "upgrade.limit.orgs.title",
        descriptionKey: "upgrade.limit.orgs.description",
        targetPlan: "pro",
    },
    remote_requires_ultimate: {
        titleKey: "upgrade.limit.remote.title",
        descriptionKey: "upgrade.limit.remote.description",
        targetPlan: "ultimate",
    },
};

export function UpgradeModal() {
    const { open, limitType, closeUpgradeModal } = useUpgradeModalStore();
    const { load } = useLicenseStore();
    const { t } = useI18n();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [pollSessionId, setPollSessionId] = useState<string | null>(null);

    const config = limitType ? LIMIT_CONFIG[limitType] : null;

    useCheckoutPoller(pollSessionId, () => {
        setPollSessionId(null);
        void load();
        closeUpgradeModal();
    });

    const handleUpgrade = async () => {
        if (!config) return;
        setLoading(true);
        setError(null);
        try {
            const checkout = await invoke<CheckoutDto>("checkout_license", {
                plan: config.targetPlan,
                cycle: "monthly",
            });
            await openUrl(checkout.url);
            setPollSessionId(checkout.sessionId);
            closeUpgradeModal();
        } catch {
            setError(t("upgrade.error.checkout"));
        } finally {
            setLoading(false);
        }
    };

    return (
        <Dialog open={open} onOpenChange={(v) => !v && closeUpgradeModal()}>
            <DialogContent className="max-w-sm">
                <DialogHeader>
                    <DialogTitle className="text-base font-semibold">
                        {config ? t(config.titleKey) : ""}
                    </DialogTitle>
                    <DialogDescription className="text-[13px] text-zinc-500 dark:text-zinc-400 mt-1">
                        {config ? t(config.descriptionKey) : ""}
                    </DialogDescription>
                </DialogHeader>

                <div className="flex flex-col gap-2 mt-2">
                    <Button
                        onClick={handleUpgrade}
                        disabled={loading}
                        className="w-full"
                    >
                        {loading
                            ? t("upgrade.cta.loading")
                            : config?.targetPlan === "ultimate"
                            ? t("upgrade.cta.ultimate")
                            : t("upgrade.cta.pro")}
                    </Button>
                    {error && (
                        <p className="text-center text-[11px] text-red-500">{error}</p>
                    )}
                    <Button
                        variant="ghost"
                        onClick={closeUpgradeModal}
                        className="w-full text-zinc-500"
                    >
                        {t("common.cancel")}
                    </Button>
                </div>
            </DialogContent>
        </Dialog>
    );
}
