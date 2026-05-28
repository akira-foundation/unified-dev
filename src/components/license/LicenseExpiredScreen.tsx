import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { Button } from "@/components/ui/button";
import { useLicense } from "@/hooks/useLicense";
import { useLicenseStore } from "@/stores/license-store";

export function LicenseExpiredScreen() {
  const { license } = useLicense();
  const verify = useLicenseStore((s) => s.verify);

  const openPortal = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
      // Portal unavailable; users can also retry verification below.
    }
  };

  return (
    <div className="flex h-screen w-screen items-center justify-center bg-background p-8">
      <div className="max-w-md space-y-6 text-center">
        <div className="space-y-2">
          <h1 className="text-2xl font-semibold tracking-tight">
            Your license is no longer active
          </h1>
          <p className="text-muted-foreground">
            {license?.status === "revoked"
              ? "We could not validate your license against the billing service. Sign in again or renew to restore access."
              : "The grace period has ended. Renew your subscription to unlock the app again."}
          </p>
        </div>
        <div className="flex justify-center gap-3">
          <Button onClick={openPortal}>Renew subscription</Button>
          <Button variant="outline" onClick={() => verify()}>
            Try again
          </Button>
        </div>
      </div>
    </div>
  );
}
