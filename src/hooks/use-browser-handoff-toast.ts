import { useCallback } from "react";
import { toast } from "sonner";

const DISMISS_DELAY_MS = 4000;
const CANCELLED_MESSAGE = "GitHub callback cancelled";

export function useBrowserHandoffToast() {
  return useCallback((loadingMessage = "Opening GitHub...") => {
    const toastId = toast.loading(loadingMessage);
    const dismissTimer = window.setTimeout(() => toast.dismiss(toastId), DISMISS_DELAY_MS);

    return {
      success(message: string) {
        window.clearTimeout(dismissTimer);
        toast.dismiss(toastId);
        toast.success(message);
      },
      error(error: unknown, fallbackMessage: string) {
        window.clearTimeout(dismissTimer);
        toast.dismiss(toastId);
        const message = typeof error === "string"
          ? error
          : error instanceof Error
            ? error.message
            : fallbackMessage;
        if (message === CANCELLED_MESSAGE) {
          return;
        }
        toast.error(message);
      },
    };
  }, []);
}
