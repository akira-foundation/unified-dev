import { useState } from "react";

import type { AppPage } from "../types/navigation";

export function useNavigation(initialPage: AppPage) {
  const [currentPage, setCurrentPage] = useState<AppPage>(initialPage);

  return {
    currentPage,
    setCurrentPage,
  };
}
