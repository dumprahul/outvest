import { readFile } from "node:fs/promises";
import path from "node:path";

// The relayer (chainlink/outvest-cre/relayer, `watch`) appends one JSON line per step it takes.
const LOG_FILE =
  process.env.RELAYER_LOG ?? path.join(process.cwd(), "..", "chainlink", "outvest-cre", "relayer", "cre-log.jsonl");

type Entry = { t: number; level: string; msg: string; tx?: string; vault?: string; wallet?: string; step?: string };

export async function GET(req: Request) {
  const url = new URL(req.url);
  const vault = url.searchParams.get("vault")?.toLowerCase();
  const wallet = url.searchParams.get("wallet")?.toLowerCase();
  let text = "";
  try {
    text = await readFile(LOG_FILE, "utf8");
  } catch {
    return Response.json({ entries: [], online: false });
  }
  const entries: Entry[] = [];
  for (const line of text.split("\n").slice(-2000)) {
    if (!line) continue;
    try {
      const e = JSON.parse(line) as Entry;
      if (vault && e.vault && e.vault.toLowerCase() !== vault) continue;
      // Per-creator lines are only shown to that creator; campaign-wide lines (snapshots, claims) are shared.
      if (wallet && e.wallet && e.wallet.toLowerCase() !== wallet) continue;
      entries.push(e);
    } catch {
      /* skip a torn line */
    }
  }
  const last = entries.at(-1)?.t ?? 0;
  return Response.json({ entries: entries.slice(-80), online: Date.now() - last < 10 * 60_000 });
}
