import { useEffect, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useLicenseStore } from "@/stores/license-store";
import { useI18n } from "@/i18n/i18n";

interface LicenseActivationDialogProps {
  open: boolean;
  onClose: () => void;
  initialSessionId?: string;
}

export function LicenseActivationDialog({ open, onClose, initialSessionId }: LicenseActivationDialogProps) {
  const { t } = useI18n();
  const { activate, loading } = useLicenseStore();
  const [sessionId, setSessionId] = useState(initialSessionId ?? "");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  // When opened via deep link, pre-fill and auto-activate
  useEffect(() => {
    if (open && initialSessionId) {
      setSessionId(initialSessionId);
      setError(null);
      handleActivate(initialSessionId);
    }
  }, [open, initialSessionId]);

  const handleActivate = async (id?: string) => {
    const target = (id ?? sessionId).trim();
    if (!target) return;
    setError(null);
    try {
      await activate(target);
      setSuccess(true);
      setTimeout(() => {
        onClose();
        setSuccess(false);
        setSessionId("");
      }, 1500);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Activation failed");
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-[420px]">
        <DialogHeader>
          <DialogTitle>{t("license.activate.title")}</DialogTitle>
          <DialogDescription>{t("license.activate.description")}</DialogDescription>
        </DialogHeader>

        {success ? (
          <div className="py-6 text-center">
            <p className="text-[14px] text-emerald-500 font-medium">{t("license.activate.success")}</p>
          </div>
        ) : (
          <div className="space-y-4 pt-2">
            <input
              type="text"
              value={sessionId}
              onChange={(e) => setSessionId(e.target.value)}
              placeholder={t("license.activate.placeholder")}
              className="w-full rounded-md border border-zinc-200 dark:border-zinc-700 bg-transparent px-3 py-2 text-[13px] text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-400 focus:outline-none focus:ring-1 focus:ring-zinc-400 dark:focus:ring-zinc-600"
              onKeyDown={(e) => { if (e.key === "Enter") handleActivate(); }}
            />
            {error && (
              <p className="text-[12px] text-red-500">{error}</p>
            )}
            <div className="flex gap-3 justify-end">
              <Button variant="outline" onClick={onClose} disabled={loading}>
                {t("common.cancel")}
              </Button>
              <Button onClick={() => handleActivate()} disabled={loading || !sessionId.trim()}>
                {loading ? t("license.activate.activating") : t("license.activate.confirm")}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
