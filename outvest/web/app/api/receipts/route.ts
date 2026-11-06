// Lists a wallet's CCIP earnings-receipt transactions (Arc send -> CCIP message -> Base Sepolia delivery).
// Public RPCs cap eth_getLogs at ~200 blocks, so this reads the chains' Blockscout indexers instead.
const SENDER = (process.env.NEXT_PUBLIC_RECEIPT_SENDER ?? "").toLowerCase();
const RECEIVER = (process.env.NEXT_PUBLIC_RECEIPT_RECEIVER ?? "").toLowerCase();
const ARC = "https://testnet.arcscan.app";
const BASE = "https://base-sepolia.blockscout.com";

type Log = { transaction_hash: string; block_timestamp: string; topics: (string | null)[]; data: string };

async function logs(host: string, address: string): Promise<Log[]> {
  const r = await fetch(`${host}/api/v2/addresses/${address}/logs`, { cache: "no-store", redirect: "follow" });
  if (!r.ok) return [];
  return ((await r.json()) as { items: Log[] }).items;
}

const pad = (a: string) => "0x" + a.toLowerCase().replace("0x", "").padStart(64, "0");

export async function GET(req: Request) {
  const wallet = new URL(req.url).searchParams.get("wallet") ?? "";
  if (!/^0x[0-9a-fA-F]{40}$/.test(wallet) || !SENDER || !RECEIVER) return Response.json({ receipts: [] });
  const w = pad(wallet);
  const [sent, stored] = await Promise.all([logs(ARC, SENDER), logs(BASE, RECEIVER)]);
  const delivered = new Map(stored.filter((l) => l.topics[1]?.toLowerCase() === w).map((l) => [l.topics[3]?.toLowerCase(), l.transaction_hash]));
  const receipts = sent
    .filter((l) => l.topics[3]?.toLowerCase() === w)
    .map((l) => ({
      messageId: l.topics[1] as string,
      arcTx: l.transaction_hash,
      baseTx: delivered.get(l.topics[1]?.toLowerCase()) ?? null,
      at: l.block_timestamp,
      paid: BigInt("0x" + l.data.slice(2 + 64, 2 + 128)).toString(),
    }));
  return Response.json({ receipts: receipts.slice(0, 5) });
}
