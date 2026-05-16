const cache = new Map<string, string>();

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input.trim().toLowerCase());
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function avatarFromEmail(email: string | null | undefined): Promise<string | undefined> {
  if (!email) return undefined;
  const cached = cache.get(email);
  if (cached) return cached;
  const hash = await sha256(email);
  const url = `https://gravatar.com/avatar/${hash}?d=identicon&s=128`;
  cache.set(email, url);
  return url;
}
