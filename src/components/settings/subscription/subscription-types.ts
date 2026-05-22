export interface PlanFeatureDto {
  key: string;
  name: string;
  description: string | null;
}

export interface PlanDto {
  id: string;
  key: string;
  name: string;
  description: string | null;
  amount: number | null;
  currency: string | null;
  billing_interval: string | null;
  trial_period_days: number;
  is_coming_soon: boolean;
  features: PlanFeatureDto[];
}

export interface ProductPlansDto {
  product: string;
  name: string;
  description: string | null;
  landing_url: string | null;
  beta_ends_at: string | null;
  beta_active: boolean;
  plans: PlanDto[];
}

export interface InvoiceDto {
  id: string;
  number: string | null;
  amount: number;
  currency: string;
  date: string;
  pdfUrl: string | null;
  hostedUrl: string | null;
}

export interface InvoicesPageDto {
  invoices: InvoiceDto[];
  hasMore: boolean;
  nextCursor: string | null;
}

export type BillingCycle = "monthly" | "yearly";

export const TIER_COLOR: Record<string, string> = {
  free: "bg-zinc-500/10 text-zinc-400 border-zinc-500/20",
  pro: "bg-blue-500/10 text-blue-400 border-blue-500/20",
  ultimate: "bg-purple-500/10 text-purple-400 border-purple-500/20",
};

export const TIER_CHECK_COLOR: Record<string, string> = {
  free: "text-zinc-400",
  pro: "text-blue-400",
  ultimate: "text-purple-400",
};

export const TIER_ORDER: Record<string, number> = { free: 0, pro: 1, ultimate: 2 };

export const RECOMMENDED_TIER = "pro";

export const PLAN_COLOR = TIER_COLOR;

export function extractTier(key: string): string {
  return key.replace(/_monthly$|_yearly$/, "");
}

export function findPlan(tier: string, cycle: BillingCycle, plans: PlanDto[]): PlanDto | undefined {
  if (tier === "free") return plans.find((p) => p.key === "free");
  const interval = cycle === "yearly" ? "year" : "month";
  return plans.find((p) => extractTier(p.key) === tier && p.billing_interval === interval);
}

export function formatPrice(amount: number | null | undefined, currency: string | null | undefined, locale: string): string {
  if (amount == null) return "—";
  const value = amount / 100;
  if (currency) {
    try {
      return new Intl.NumberFormat(locale, { style: "currency", currency: currency.toUpperCase(), maximumFractionDigits: 0 }).format(value);
    } catch {
    }
  }
  return value === 0 ? "€0" : `€${value}`;
}
