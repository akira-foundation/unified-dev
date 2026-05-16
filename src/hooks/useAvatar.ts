import { useEffect, useState } from "react";
import { avatarFromEmail } from "@/lib/avatar";

export function useAvatar(email: string | null | undefined): string | undefined {
  const [url, setUrl] = useState<string | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void avatarFromEmail(email).then((value) => {
      if (!cancelled) setUrl(value);
    });
    return () => {
      cancelled = true;
    };
  }, [email]);

  return url;
}
