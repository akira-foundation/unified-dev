import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useUpgradeModalStore, type FreeTierLimitType } from "@/stores/upgrade-modal-store";
import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";

const LIMIT_CONFIG: Record<FreeTierLimitType, {
    titleKey: string;
    descriptionKey: string;
    targetPlan: "pro" | "ultimate";
    featureKey?: string;
}> = {
    run_limit_reached: {
        titleKey: "upgrade.limit.runs.title",
        descriptionKey: "upgrade.limit.runs.description",
        targetPlan: "pro",
        featureKey: "agent_run",
    },
    thread_limit_reached: {
        titleKey: "upgrade.limit.threads.title",
        descriptionKey: "upgrade.limit.threads.description",
        targetPlan: "pro",
        featureKey: "threads",
    },
    repo_limit_reached: {
        titleKey: "upgrade.limit.repos.title",
        descriptionKey: "upgrade.limit.repos.description",
        targetPlan: "pro",
        featureKey: "repos",
    },
    org_limit_reached: {
        titleKey: "upgrade.limit.orgs.title",
        descriptionKey: "upgrade.limit.orgs.description",
        targetPlan: "pro",
        featureKey: "orgs",
    },
    remote_requires_ultimate: {
        titleKey: "upgrade.limit.remote.title",
        descriptionKey: "upgrade.limit.remote.description",
        targetPlan: "ultimate",
    },
    autopilot_requires_pro: {
        titleKey: "upgrade.limit.autopilot.title",
        descriptionKey: "upgrade.limit.autopilot.description",
        targetPlan: "pro",
    },
};

interface UsageSnapshot {
    runCount: number;
    runLimit: number | null;
}

export function UpgradeModal() {
    const { open, limitType, context, closeUpgradeModal } = useUpgradeModalStore();
    const { t } = useI18n();
    const navigateTo = useNavigationStore((s) => s.navigateTo);
    const setSettingsTab = useNavigationStore((s) => s.setSettingsTab);
    const [usage, setUsage] = useState<UsageSnapshot | null>(null);

    const config = limitType ? LIMIT_CONFIG[limitType] : null;
    const featureKey = config?.featureKey;

    useEffect(() => {
        if (!open || !featureKey) {
            setUsage(null);
            return;
        }
        let active = true;
        invoke<UsageSnapshot>("get_feature_usage", { feature: featureKey })
            .then((res) => {
                if (active) setUsage(res);
            })
            .catch(() => {
                if (active) setUsage(null);
            });
        return () => {
            active = false;
        };
    }, [open, featureKey]);

    const vars: Record<string, string> = {};
    if (featureKey) {
        const count = context.count ?? usage?.runCount ?? 0;
        const limit = context.limit ?? usage?.runLimit ?? 0;
        vars.count = String(count);
        vars.limit = String(limit);
    }

    const handleUpgrade = () => {
        closeUpgradeModal();
        setSettingsTab("subscription");
        navigateTo("settings");
    };

    return (
        <Dialog open={open} onOpenChange={(v) => !v && closeUpgradeModal()}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{config ? t(config.titleKey) : ""}</DialogTitle>
                    <DialogDescription>
                        {config ? t(config.descriptionKey, vars) : ""}
                    </DialogDescription>
                </DialogHeader>

                <DialogFooter>
                    <Button variant="outline" onClick={closeUpgradeModal}>
                        {t("common.cancel")}
                    </Button>
                    <Button onClick={handleUpgrade}>
                        {config?.targetPlan === "ultimate"
                            ? t("upgrade.cta.ultimate")
                            : t("upgrade.cta.pro")}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
}
