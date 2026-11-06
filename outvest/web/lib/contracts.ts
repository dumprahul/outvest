import { createPublicClient, defineChain, http, parseAbi, type Hex } from "viem";

export const arc = defineChain({
  id: 5042002,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [process.env.NEXT_PUBLIC_ARC_RPC ?? "https://rpc.testnet.arc.io"] } },
  blockExplorers: { default: { name: "Arcscan", url: "https://testnet.arcscan.app" } },
});

/** Factory whose identity is locked; set per environment. */
export const FACTORY = (process.env.NEXT_PUBLIC_FACTORY ?? "") as Hex;
export const USDC = "0x3600000000000000000000000000000000000000" as Hex;
export const USDC_DECIMALS = 6;

// The public RPC rate-limits aggressively; retry with backoff instead of failing the page.
export const publicClient = createPublicClient({
  chain: arc,
  transport: http(undefined, { retryCount: 6, retryDelay: 700 }),
});

export const factoryAbi = parseAbi([
  "function campaignCount() view returns (uint256)",
  "function campaignAt(uint256) view returns (address)",
  "function identityLocked() view returns (bool)",
]);

export const vaultAbi = parseAbi([
  "function brand() view returns (address)",
  "function totalFunded() view returns (uint256)",
  "function totalPaid() view returns (uint256)",
  "function liability() view returns (uint256)",
  "function creatorCount() view returns (uint256)",
  "function maxCreators() view returns (uint32)",
  "function capPerCreator() view returns (uint256)",
  "function ratePerThousand() view returns (uint256)",
  "function upfrontPpm() view returns (uint32)",
  "function bindDeadline() view returns (uint64)",
  "function finalized() view returns (bool)",
  "function claimable(address) view returns (uint256)",
  "function pendingBinding(address) view returns (bytes32 videoId, bytes32 challenge, uint64 requestedAt, uint64 lastSubmitTs, uint32 nonce)",
  "function creatorInfo(address) view returns ((bool bound, bool settled, uint64 boundAt, uint16 videoCount, uint128 paid, uint128 remaining, uint128 creditedViews, uint128 upfront, bytes32[10] videoIds))",
  "function videosOf(address) view returns (bytes32[])",
]);

export const usdcAbi = parseAbi(["function balanceOf(address) view returns (uint256)", "function allowance(address,address) view returns (uint256)"]);

export interface CampaignView {
  vault: Hex;
  brand: Hex;
  totalFunded: bigint;
  totalPaid: bigint;
  liability: bigint;
  creatorCount: bigint;
  maxCreators: number;
  cap: bigint;
  rate: bigint;
  upfrontPpm: number;
  bindDeadline: bigint;
  finalized: boolean;
}

const read = <T,>(address: Hex, fn: string, args: unknown[] = []) =>
  publicClient.readContract({ address, abi: vaultAbi, functionName: fn, args } as never) as Promise<T>;

export async function loadCampaign(vault: Hex): Promise<CampaignView> {
  const [brand, totalFunded, totalPaid, liability, creatorCount, maxCreators, cap, rate, upfrontPpm, bindDeadline, finalized] =
    await Promise.all([
      read<Hex>(vault, "brand"), read<bigint>(vault, "totalFunded"), read<bigint>(vault, "totalPaid"),
      read<bigint>(vault, "liability"), read<bigint>(vault, "creatorCount"), read<number>(vault, "maxCreators"),
      read<bigint>(vault, "capPerCreator"), read<bigint>(vault, "ratePerThousand"), read<number>(vault, "upfrontPpm"),
      read<bigint>(vault, "bindDeadline"), read<boolean>(vault, "finalized"),
    ]);
  return { vault, brand, totalFunded, totalPaid, liability, creatorCount, maxCreators, cap, rate, upfrontPpm, bindDeadline, finalized };
}

/** Newest-first campaigns from the factory (capped to keep RPC usage small). */
export async function loadCampaigns(limit = 12): Promise<CampaignView[]> {
  if (!FACTORY) return [];
  const count = await publicClient.readContract({ address: FACTORY, abi: factoryAbi, functionName: "campaignCount" });
  const n = Math.min(Number(count), limit);
  const vaults = await Promise.all(
    Array.from({ length: n }, (_, i) =>
      publicClient.readContract({ address: FACTORY, abi: factoryAbi, functionName: "campaignAt", args: [count - 1n - BigInt(i)] }),
    ),
  );
  return Promise.all(vaults.map((v) => loadCampaign(v as Hex)));
}

export const fmtUsdc = (v: bigint): string => {
  const whole = v / 10n ** BigInt(USDC_DECIMALS);
  const frac = (v % 10n ** BigInt(USDC_DECIMALS)).toString().padStart(USDC_DECIMALS, "0").slice(0, 2);
  return `${whole.toLocaleString("en-US")}.${frac}`;
};
export const toUnits = (usdc: number): bigint => BigInt(Math.round(usdc * 10 ** USDC_DECIMALS));
export const explorerAddress = (a: string) => `${arc.blockExplorers.default.url}/address/${a}`;

/** YouTube id (11 chars) -> bytes32 hex, ASCII left-aligned. */
export function videoIdToBytes32(id: string): Hex {
  if (!/^[A-Za-z0-9_-]{11}$/.test(id)) throw new Error("Enter the 11-character YouTube video id");
  const hex = Array.from(id).map((c) => c.charCodeAt(0).toString(16).padStart(2, "0")).join("");
  return `0x${hex.padEnd(64, "0")}` as Hex;
}
export function bytes32ToVideoId(b: string): string | null {
  const hex = b.replace(/^0x/, "");
  if (hex.length !== 64 || hex.slice(22) !== "0".repeat(42)) return null;
  const s = hex.slice(0, 22).match(/../g)!.map((h) => String.fromCharCode(parseInt(h, 16))).join("");
  return /^[A-Za-z0-9_-]{11}$/.test(s) ? s : null;
}
