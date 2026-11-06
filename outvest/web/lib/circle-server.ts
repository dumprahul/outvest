import "server-only";

const BASE_URL = process.env.CIRCLE_BASE_URL ?? "https://api.circle.com";

/** Chain every OutVest wallet is created on. Mainnet is gated on CRE support (see architecture §10). */
export const WALLET_BLOCKCHAIN = process.env.CIRCLE_BLOCKCHAIN ?? "ARC-TESTNET";

export class CircleError extends Error {
  constructor(
    message: string,
    public status: number,
    public code?: number,
  ) {
    super(message);
  }
}

interface CircleRequest {
  method: "GET" | "POST";
  path: string;
  body?: Record<string, unknown>;
  userToken?: string;
}

/**
 * The only place the Circle API key is read. Never import this from client code
 * ("server-only" makes the build fail if someone does).
 */
export async function circle<T>({ method, path, body, userToken }: CircleRequest): Promise<T> {
  const apiKey = process.env.CIRCLE_API_KEY;
  if (!apiKey) throw new CircleError("CIRCLE_API_KEY is not configured", 500);

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    cache: "no-store",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      ...(userToken ? { "X-User-Token": userToken } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const json = (await res.json().catch(() => ({}))) as {
    data?: T;
    message?: string;
    code?: number;
  };
  if (!res.ok) {
    throw new CircleError(json.message ?? `Circle request failed (${res.status})`, res.status, json.code);
  }
  return json.data as T;
}
