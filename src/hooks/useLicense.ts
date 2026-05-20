import { useEffect } from "react";
import { useLicenseStore, type Plan } from "@/stores/license-store";

export function useLicense() {
  const { license, loading, load, plan } = useLicenseStore();

  useEffect(() => {
    load();
  }, []);

  const currentPlan: Plan = plan();
  const isActive = license?.status === "active";
  const isPro = currentPlan === "pro" || currentPlan === "ultimate";
  const isUltimate = currentPlan === "ultimate";

  return { license, loading, load, currentPlan, isActive, isPro, isUltimate };
}
