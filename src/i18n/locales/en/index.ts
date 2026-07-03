import { enAgenda } from "./agenda";
import { enAgents } from "./agents";
import { enApp } from "./app";
import { enAppearance } from "./appearance";
import { enAutopilot } from "./autopilot";
import { enCommon } from "./common";
import { enComponents } from "./components";
import { enCurrency } from "./currency";
import { enDashboard } from "./dashboard";
import { enDialogs } from "./dialogs";
import { enFilters } from "./filters";
import { enGhCliError } from "./ghCliError";
import { enImport } from "./import";
import { enIssues } from "./issues";
import { enKanban } from "./kanban";
import { enLinkRepo } from "./linkRepo";
import { enModal } from "./modal";
import { enNav } from "./nav";
import { enOpenSource } from "./openSource";
import { enPages } from "./pages";
import { enPrs } from "./prs";
import { enRepos } from "./repos";
import { enRepositories } from "./repositories";
import { enSearch } from "./search";
import { enSettingsAppearance } from "./settings/appearance";
import { enSettingsBehaviour } from "./settings/behaviour";
import { enSettingsGeneral } from "./settings/general";
import { enSettingsMisc } from "./settings/misc";
import { enSettingsNotifications } from "./settings/notifications";
import { enSettingsProjects } from "./settings/projects";
import { enSettingsPrompts } from "./settings/prompts";
import { enSettingsRemote } from "./settings/remote";
import { enSettingsShortcuts } from "./settings/shortcuts";
import { enSettingsSync } from "./settings/sync";
import { enSettingsTabs } from "./settings/tabs";
import { enSettingsUpdates } from "./settings/updates";
import { enSidebar } from "./sidebar";
import { enTables } from "./tables";
import { enToast } from "./toast";
import { enToolbar } from "./toolbar";
import { enVisibility } from "./visibility";

export const en: Record<string, string> = {
  ...enAgenda,
  ...enAgents,
  ...enApp,
  ...enAppearance,
  ...enAutopilot,
  ...enCommon,
  ...enComponents,
  ...enCurrency,
  ...enDashboard,
  ...enDialogs,
  ...enFilters,
  ...enGhCliError,
  ...enImport,
  ...enIssues,
  ...enKanban,
  ...enLinkRepo,
  ...enModal,
  ...enNav,
  ...enOpenSource,
  ...enPages,
  ...enPrs,
  ...enRepos,
  ...enRepositories,
  ...enSearch,
  ...enSettingsAppearance,
  ...enSettingsBehaviour,
  ...enSettingsGeneral,
  ...enSettingsMisc,
  ...enSettingsNotifications,
  ...enSettingsProjects,
  ...enSettingsPrompts,
  ...enSettingsRemote,
  ...enSettingsShortcuts,
  ...enSettingsSync,
  ...enSettingsTabs,
  ...enSettingsUpdates,
  ...enSidebar,
  ...enTables,
  ...enToast,
  ...enToolbar,
  ...enVisibility,
};
