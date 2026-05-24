import { useNavigationStore } from "@/stores/navigation-store";

export interface NotificationActionTarget {
  action_type: string | null;
  action_payload: string | null;
}

export function hasAction(item: NotificationActionTarget): boolean {
  return !!item.action_type;
}

export function actionLabel(action_type: string | null): string | null {
  if (!action_type) return null;
  switch (action_type) {
    case "update.cli":
      return "Update";
    case "upgrade.pro":
      return "Upgrade";
    case "autopilot.open":
      return "Open job";
    case "github.install":
      return "Install App";
    case "auth.reconnect":
      return "Sign in";
    default:
      return null;
  }
}

export function runAction(item: NotificationActionTarget): void {
  if (!item.action_type) return;

  const nav = useNavigationStore.getState();

  switch (item.action_type) {
    case "upgrade.pro": {
      nav.setSettingsTab("subscription");
      nav.navigateTo("settings");
      return;
    }
    case "autopilot.open": {
      nav.navigateTo("agents");
      return;
    }
    case "auth.reconnect":
    case "github.install": {
      nav.setSettingsTab("vcs-providers");
      nav.navigateTo("settings");
      return;
    }
    case "update.cli": {
      return;
    }
    default:
      return;
  }
}
