import { NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { circle, CircleError, WALLET_BLOCKCHAIN } from "@/lib/circle-server";

/**
 * Thin, allowlisted proxy to Circle's user-controlled wallets API.
 *
 * No privileged power lives here: the user's own userToken (issued by Circle
 * after email OTP) authorizes every wallet call, and PIN / signing happen in
 * Circle's hosted UI, so this server never sees keys or PINs.
 */

type Body = Record<string, unknown>;

const str = (v: unknown, name: string, max = 4096): string => {
  if (typeof v !== "string" || !v || v.length > max) {
    throw new CircleError(`Invalid ${name}`, 400);
  }
  return v;
};

const ADDR_RE = /^0x[0-9a-fA-F]{40}$/;

/** Only these OutVest calls can be turned into signing challenges by this proxy. */
const ALLOWED_SIGNATURES = new Set([
  "approve(address,uint256)",
  "fund(uint256)",
  "requestBinding(bytes32)",
  "submitForVerification()",
  "claim(address)",
  "settle(address)",
  "sweep()",
  "sendReceipt(uint64,address,address,address)",
  "createCampaign((address,address,uint64,uint256,uint256,uint32,uint8,uint32,uint64,uint64,uint64,uint256,uint32,(uint32,uint32,uint32)[]))",
]);

const decimal = (v: unknown): string => {
  if (typeof v !== "string" || !/^\d{1,6}(\.\d{1,18})?$/.test(v)) throw new CircleError("Invalid amount", 400);
  return v;
};

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const handlers: Record<string, (b: Body) => Promise<unknown>> = {
  async requestEmailOtp(b) {
    const email = str(b.email, "email", 254);
    if (!EMAIL_RE.test(email)) throw new CircleError("Invalid email", 400);
    return circle({
      method: "POST",
      path: "/v1/w3s/users/email/token",
      body: { idempotencyKey: randomUUID(), deviceId: str(b.deviceId, "deviceId", 128), email },
    });
  },

  async requestSocialToken(b) {
    return circle({
      method: "POST",
      path: "/v1/w3s/users/social/token",
      body: { idempotencyKey: randomUUID(), deviceId: str(b.deviceId, "deviceId", 128) },
    });
  },

  async initializeUser(b) {
    try {
      return await circle({
        method: "POST",
        path: "/v1/w3s/user/initialize",
        userToken: str(b.userToken, "userToken"),
        body: {
          idempotencyKey: randomUUID(),
          accountType: "SCA",
          blockchains: [WALLET_BLOCKCHAIN],
        },
      });
    } catch (e) {
      // 155106: user already initialized -> client should just load the existing wallet.
      if (e instanceof CircleError && e.code === 155106) return { alreadyInitialized: true };
      throw e;
    }
  },

  /** Creates a contract-execution challenge; the user approves it with their PIN in Circle's UI. */
  async executeContract(b) {
    const walletId = str(b.walletId, "walletId", 64);
    if (!/^[\w-]+$/.test(walletId)) throw new CircleError("Invalid walletId", 400);
    const contractAddress = str(b.contractAddress, "contractAddress", 42);
    if (!ADDR_RE.test(contractAddress)) throw new CircleError("Invalid contractAddress", 400);
    const sig = str(b.abiFunctionSignature, "abiFunctionSignature", 400);
    if (!ALLOWED_SIGNATURES.has(sig)) throw new CircleError("Function not allowed", 400);
    if (!Array.isArray(b.abiParameters)) throw new CircleError("Invalid abiParameters", 400);
    return circle({
      method: "POST",
      path: "/v1/w3s/user/transactions/contractExecution",
      userToken: str(b.userToken, "userToken"),
      body: {
        idempotencyKey: randomUUID(),
        walletId,
        contractAddress,
        abiFunctionSignature: sig,
        abiParameters: b.abiParameters,
        // Native-token value (whole units, e.g. "0.15"); only the CCIP receipt call needs it.
        ...(b.amount === undefined ? {} : { amount: decimal(b.amount) }),
        feeLevel: "MEDIUM",
      },
    });
  },

  async listWallets(b) {
    return circle({ method: "GET", path: "/v1/w3s/wallets", userToken: str(b.userToken, "userToken") });
  },

  async getBalances(b) {
    const walletId = str(b.walletId, "walletId", 64);
    if (!/^[\w-]+$/.test(walletId)) throw new CircleError("Invalid walletId", 400);
    return circle({
      method: "GET",
      path: `/v1/w3s/wallets/${walletId}/balances`,
      userToken: str(b.userToken, "userToken"),
    });
  },
};

export async function POST(req: Request, ctx: { params: Promise<{ action: string }> }) {
  const { action } = await ctx.params;
  const handler = Object.hasOwn(handlers, action) ? handlers[action] : undefined;
  if (!handler) return NextResponse.json({ error: "Unknown action" }, { status: 404 });

  try {
    const body = (await req.json().catch(() => ({}))) as Body;
    return NextResponse.json(await handler(body));
  } catch (e) {
    if (e instanceof CircleError) {
      return NextResponse.json({ error: e.message, code: e.code }, { status: e.status });
    }
    console.error("circle route error", e);
    return NextResponse.json({ error: "Unexpected error" }, { status: 500 });
  }
}
