import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";

type PaymentStatus = "past_due" | "unpaid" | "canceled" | "incomplete_expired" | "incomplete";

const COPY: Record<PaymentStatus, { title: string; body: string; tone: "warn" | "danger" }> = {
  past_due: {
    title: "Payment failed",
    body: "Your latest invoice could not be charged. Update your payment method before the current period ends to keep Pro access.",
    tone: "warn",
  },
  unpaid: {
    title: "Subscription suspended",
    body: "Stripe stopped retrying your invoice. Update your payment method now to restore Pro access.",
    tone: "danger",
  },
  canceled: {
    title: "Subscription canceled",
    body: "Your subscription has been canceled. You can resubscribe from the billing portal at any time.",
    tone: "danger",
  },
  incomplete_expired: {
    title: "Checkout expired",
    body: "Your previous checkout was not completed in time. Start a new checkout to activate Pro.",
    tone: "warn",
  },
  incomplete: {
    title: "Finish checkout",
    body: "Your subscription is waiting on payment confirmation. Complete the checkout to activate Pro.",
    tone: "warn",
  },
};

interface LicensePaymentStatusBannerProps {
  paymentStatus?: PaymentStatus | string | null;
}

export function LicensePaymentStatusBanner({ paymentStatus }: LicensePaymentStatusBannerProps) {
  const key = paymentStatus as PaymentStatus | undefined;
  if (!key || !(key in COPY)) return null;

  const copy = COPY[key];
  const isDanger = copy.tone === "danger";

  const openPortal = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
    }
  };

  const containerClass = isDanger
    ? "flex items-center justify-between gap-3 border-b border-red-400/40 bg-red-50/95 px-4 py-2 text-sm text-red-900 dark:bg-red-950/40 dark:text-red-100"
    : "flex items-center justify-between gap-3 border-b border-amber-400/40 bg-amber-50/95 px-4 py-2 text-sm text-amber-900 dark:bg-amber-950/40 dark:text-amber-100";

  const iconClass = isDanger ? "h-4 w-4 text-red-500" : "h-4 w-4 text-amber-500";

  return (
    <div role="status" className={containerClass}>
      <div className="flex items-center gap-2">
        <AlertTriangle className={iconClass} />
        <span>
          <span className="font-semibold">{copy.title}.</span> {copy.body}
        </span>
      </div>
      <Button size="sm" variant="outline" onClick={openPortal}>
        Update payment method
      </Button>
    </div>
  );
}
