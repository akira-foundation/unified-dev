import { ptAgenda } from "./agenda";
import { ptAgents } from "./agents";
import { ptApp } from "./app";
import { ptAppearance } from "./appearance";
import { ptAutopilot } from "./autopilot";
import { ptCommon } from "./common";
import { ptComponents } from "./components";
import { ptCurrency } from "./currency";
import { ptDashboard } from "./dashboard";
import { ptDialogs } from "./dialogs";
import { ptFilters } from "./filters";
import { ptGhCliError } from "./ghCliError";
import { ptImport } from "./import";
import { ptIssues } from "./issues";
import { ptKanban } from "./kanban";
import { ptLinkRepo } from "./linkRepo";
import { ptModal } from "./modal";
import { ptNav } from "./nav";
import { ptOpenSource } from "./openSource";
import { ptPages } from "./pages";
import { ptPrs } from "./prs";
import { ptRepos } from "./repos";
import { ptRepositories } from "./repositories";
import { ptSearch } from "./search";
import { ptSettingsAppearance } from "./settings/appearance";
import { ptSettingsBehaviour } from "./settings/behaviour";
import { ptSettingsGeneral } from "./settings/general";
import { ptSettingsMisc } from "./settings/misc";
import { ptSettingsNotifications } from "./settings/notifications";
import { ptSettingsProjects } from "./settings/projects";
import { ptSettingsPrompts } from "./settings/prompts";
import { ptSettingsRemote } from "./settings/remote";
import { ptSettingsShortcuts } from "./settings/shortcuts";
import { ptSettingsSync } from "./settings/sync";
import { ptSettingsTabs } from "./settings/tabs";
import { ptSettingsUpdates } from "./settings/updates";
import { ptSidebar } from "./sidebar";
import { ptTables } from "./tables";
import { ptToast } from "./toast";
import { ptToolbar } from "./toolbar";
import { ptUpgrade } from "./upgrade";
import { ptVisibility } from "./visibility";

export const pt: Record<string, string> = {
  ...ptAgenda,
  ...ptAgents,
  ...ptApp,
  ...ptAppearance,
  ...ptAutopilot,
  ...ptCommon,
  ...ptComponents,
  ...ptCurrency,
  ...ptDashboard,
  ...ptDialogs,
  ...ptFilters,
  ...ptGhCliError,
  ...ptImport,
  ...ptIssues,
  ...ptKanban,
  ...ptLinkRepo,
  ...ptModal,
  ...ptNav,
  ...ptOpenSource,
  ...ptPages,
  ...ptPrs,
  ...ptRepos,
  ...ptRepositories,
  ...ptSearch,
  ...ptSettingsAppearance,
  ...ptSettingsBehaviour,
  ...ptSettingsGeneral,
  ...ptSettingsMisc,
  ...ptSettingsNotifications,
  ...ptSettingsProjects,
  ...ptSettingsPrompts,
  ...ptSettingsRemote,
  ...ptSettingsShortcuts,
  ...ptSettingsSync,
  ...ptSettingsTabs,
  ...ptSettingsUpdates,
  ...ptSidebar,
  ...ptTables,
  ...ptToast,
  ...ptToolbar,
  ...ptUpgrade,
  ...ptVisibility,
};
