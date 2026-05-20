import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
import { useEffect, useState } from "react";

export function useAutostart() {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    isEnabled()
      .then(setEnabled)
      .finally(() => setLoading(false));
  }, []);

  async function toggle(value: boolean) {
    if (value) {
      await enable();
    } else {
      await disable();
    }
    setEnabled(value);
  }

  return { enabled, loading, toggle };
}
