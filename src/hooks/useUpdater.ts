import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useState } from "react";

interface UpdateInfo {
    version: string;
    currentVersion: string;
    body: string | null;
}

interface UseUpdaterReturn {
    update: UpdateInfo | null;
    checking: boolean;
    installing: boolean;
    check: () => Promise<void>;
    install: () => Promise<void>;
}

export function useUpdater(): UseUpdaterReturn {
    const [update, setUpdate] = useState<UpdateInfo | null>(null);
    const [checking, setChecking] = useState(false);
    const [installing, setInstalling] = useState(false);

    const check = useCallback(async () => {
        setChecking(true);
        try {
            const result = await invoke<UpdateInfo | null>("check_for_updates");
            setUpdate(result);
        } catch {
            // silently ignore — updater may not be available in dev
        } finally {
            setChecking(false);
        }
    }, []);

    const install = useCallback(async () => {
        setInstalling(true);
        try {
            await invoke("install_update");
        } finally {
            setInstalling(false);
        }
    }, []);

    useEffect(() => {
        check();
    }, [check]);

    return { update, checking, installing, check, install };
}
