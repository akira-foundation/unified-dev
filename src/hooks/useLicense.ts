import { useEffect } from "react";
import {
  isActiveStatus,
  isBlockingStatus,
  useLicenseStore,
  type Plan,
} from "@/stores/license-store";

export function useLicense() {
  const { license, loading, load, plan } = useLicenseStore();

  useEffect(() => {
    load();
  }, []);

  const currentPlan: Plan = plan();
  const isActive = !!license && isActiveStatus(license.status);
  const isInGrace = license?.status === "grace" || !!license?.gracePeriod;
  const isExpired = !!license && isBlockingStatus(license.status);
  const isPro = currentPlan === "pro" || currentPlan === "ultimate";
  const isUltimate = currentPlan === "ultimate";

  return {
    license,
    loading,
    load,
    currentPlan,
    isActive,
    isInGrace,
    isExpired,
    isPro,
    isUltimate,
  };
}
