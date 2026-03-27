import { useState } from "react";
import { Wrench, Shield, Trash2, AlertTriangle } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function AdvancedTab() {
  const { t } = useI18n();
  const [showResetConfirm, setShowResetConfirm] = useState(false);

  const handleClearHistory = () => {
    localStorage.removeItem("noxdireit_recent_searches");
    toast.success(t("toast.historyCleared"));
  };

  const handleClearSaved = () => {
    if (window.confirm(t("modal.reset.desc"))) {
      localStorage.removeItem("noxdireit_saved_laws");
      localStorage.removeItem("noxdireit_saved_drafts");
      localStorage.removeItem("noxdireit_saved_meetings");
      localStorage.removeItem("noxdireit_saved_checklists");
      toast.success(t("toast.savedCleared"));
    }
  };

  const handleFactoryReset = () => {
    localStorage.clear();
    toast.success(t("toast.appReset"));
    setTimeout(() => window.location.reload(), 1500);
  };

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.advanced.title")} description={t("settings.advanced.description")} icon={Wrench}>
        <SettingsItem
          label={t("settings.advanced.debug.label")}
          description={t("settings.advanced.debug.description")}
          action={<Switch />}
        />
      </SettingsSection>
      <SettingsSection
        title={t("settings.section.privacy")}
        description={t("settings.advanced.privacy.description")}
        icon={Shield}
      >
        <SettingsItem
          label={t("settings.privacy.clearHistory")}
          description={t("settings.privacy.clearHistoryDesc")}
          action={
            <button
              onClick={handleClearHistory}
              className="text-sm font-bold text-purple-500 hover:text-purple-400 transition-colors"
            >
              {t("settings.privacy.clear")}
            </button>
          }
        />
        <SettingsItem
          label={t("settings.privacy.clearSaved")}
          description={t("settings.privacy.clearSavedDesc")}
          action={
            <button
              onClick={handleClearSaved}
              className="text-sm font-bold text-rose-500 hover:text-rose-400 transition-colors"
            >
              {t("settings.privacy.clearAll")}
            </button>
          }
        />
        <SettingsItem
          label={t("settings.privacy.reset")}
          description={t("settings.privacy.resetDesc")}
          destructive
          action={
            <button
              onClick={() => setShowResetConfirm(true)}
              className="flex h-8 w-8 items-center justify-center rounded-full bg-red-500/10 text-red-500 transition-colors hover:bg-red-500/20"
            >
              <Trash2 size={16} />
            </button>
          }
        />
      </SettingsSection>

      <Dialog open={showResetConfirm} onOpenChange={setShowResetConfirm}>
        <DialogContent className="max-w-sm bg-background">
          <DialogHeader>
            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-600 dark:bg-red-500/10 dark:text-red-500">
              <AlertTriangle size={24} />
            </div>
            <DialogTitle className="text-center">{t("modal.reset.title")}</DialogTitle>
            <DialogDescription className="text-center">
              {t("modal.reset.desc")}
            </DialogDescription>
          </DialogHeader>
          <div className="flex gap-3 pt-2">
            <Button
              variant="outline"
              className="flex-1"
              onClick={() => setShowResetConfirm(false)}
            >
              {t("modal.reset.cancel")}
            </Button>
            <Button
              variant="destructive"
              className="flex-1"
              onClick={handleFactoryReset}
            >
              {t("modal.reset.confirm")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
