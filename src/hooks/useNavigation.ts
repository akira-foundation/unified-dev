import { useEffect } from "react";

import type { AppPage } from "../types/navigation";
import { useNavigationStore } from "../stores/navigation-store";

export function useNavigation(initialPage: AppPage) {
  const { currentPage, setCurrentPage, activeOrganizationId, setActiveOrganizationId } = useNavigationStore();

  useEffect(() => {
    if (currentPage === "dashboard" && initialPage !== "dashboard") {
      setCurrentPage(initialPage);
    }
  }, [currentPage, initialPage, setCurrentPage]);

  return {
    currentPage,
    setCurrentPage,
    activeOrganizationId,
    setActiveOrganizationId,
  };
}
