import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { Button } from "@/components/ui/button";
import { useLicense } from "@/hooks/useLicense";

export function LicenseGraceBanner() {
  const { isInGrace, license } = useLicense();
  if (!isInGrace || !license) return null;

  const validUntil = license.validUntil
    ? new Date(license.validUntil).toLocaleDateString()
    : null;

  const openPortal = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
      // Fall back silently; users can also renew via Settings.
    }
  };

  return (
    <div
      role="status"
      className="flex items-center justify-between gap-3 border-b border-amber-400/40 bg-amber-50/95 px-4 py-2 text-sm text-amber-900 dark:bg-amber-950/40 dark:text-amber-100"
    >
      <span>
        Your license is in the grace period
        {validUntil ? ` (ended ${validUntil})` : ""}. Renew to keep using paid
        features without interruption.
      </span>
      <Button size="sm" variant="outline" onClick={openPortal}>
        Renew now
      </Button>
    </div>
  );
}
