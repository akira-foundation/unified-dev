import { invoke } from "@tauri-apps/api/core";

export interface UpdateSettings {
  backupBeforeUpdate: boolean;
  backupPath: string | null;
}

export async function getUpdateSettings(): Promise<UpdateSettings> {
  return invoke<UpdateSettings>("get_update_settings");
}

export async function setUpdateSettings(settings: UpdateSettings): Promise<UpdateSettings> {
  return invoke<UpdateSettings>("set_update_settings", { settings });
}

export async function backupDatabaseNow(targetVersion?: string): Promise<string | null> {
  return invoke<string | null>("backup_database_now", { targetVersion: targetVersion ?? null });
}
