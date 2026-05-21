import { useQuery } from "@tanstack/react-query";

import { AgendaView } from "@/components/agenda-view";
import { SyncSettingsTab } from "@/components/settings/sync-settings-tab";
import { useOrganizations } from "@/hooks/useOrganizations";
import { cache } from "@/config/cache";
import { queryKeys } from "@/lib/query-keys";
import { repositorySelectionService } from "@/services/repositorySelectionService";

export function SyncTab() {
  const { organizations } = useOrganizations();

  const { data: allRepos = [] } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  return (
    <div className="space-y-6">
      <AgendaView organizations={organizations} allRepos={allRepos} />
      <SyncSettingsTab />
    </div>
  );
}
