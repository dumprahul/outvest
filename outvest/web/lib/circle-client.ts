export type Role = "brand" | "creator";

export interface Wallet {
  id: string;
  address: string;
  blockchain: string;
  state: string;
}

export interface TokenBalance {
  amount: string;
  token: { symbol?: string; name?: string };
}

export async function circleApi<T>(action: string, body: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`/api/circle/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error ?? "Request failed");
  return json as T;
}

export const usdcBalance = (balances: TokenBalance[]): string =>
  balances.find((b) => /usdc/i.test(b.token.symbol ?? b.token.name ?? ""))?.amount ?? "0";

/** Per-tab session: Circle userTokens are short-lived, so sessionStorage is the right scope. */
const SESSION_KEY = "outvest.circle.session";
const ROLE_KEY = "outvest.role";
const DEVICE_KEY = "outvest.deviceId";

export interface Session {
  userToken: string;
  encryptionKey: string;
  email: string;
}

const safe = {
  get: (s: Storage, k: string) => {
    try {
      return s.getItem(k);
    } catch {
      return null;
    }
  },
  set: (s: Storage, k: string, v: string) => {
    try {
      s.setItem(k, v);
    } catch {}
  },
  del: (s: Storage, k: string) => {
    try {
      s.removeItem(k);
    } catch {}
  },
};

export const sessionStore = {
  load(): Session | null {
    const raw = safe.get(sessionStorage, SESSION_KEY);
    try {
      return raw ? (JSON.parse(raw) as Session) : null;
    } catch {
      return null;
    }
  },
  save: (s: Session) => safe.set(sessionStorage, SESSION_KEY, JSON.stringify(s)),
  clear: () => safe.del(sessionStorage, SESSION_KEY),
};

export const roleStore = {
  load: (): Role | null => {
    const v = safe.get(localStorage, ROLE_KEY);
    return v === "brand" || v === "creator" ? v : null;
  },
  save: (r: Role) => safe.set(localStorage, ROLE_KEY, r),
};

export const deviceStore = {
  load: () => safe.get(localStorage, DEVICE_KEY),
  save: (id: string) => safe.set(localStorage, DEVICE_KEY, id),
};

/** Device tokens must survive the Google redirect; same-tab, so sessionStorage is enough. */
const PENDING_KEY = "outvest.circle.pendingLogin";

export interface PendingLogin {
  deviceToken: string;
  deviceEncryptionKey: string;
}

export const pendingLoginStore = {
  load(): PendingLogin | null {
    const raw = safe.get(sessionStorage, PENDING_KEY);
    try {
      return raw ? (JSON.parse(raw) as PendingLogin) : null;
    } catch {
      return null;
    }
  },
  save: (p: PendingLogin) => safe.set(sessionStorage, PENDING_KEY, JSON.stringify(p)),
  clear: () => safe.del(sessionStorage, PENDING_KEY),
};
