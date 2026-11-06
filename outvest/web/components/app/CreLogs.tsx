"use client";

import { useEffect, useRef, useState } from "react";

type Entry = { t: number; level: string; msg: string; tx?: string; step?: string };

const TONE: Record<string, string> = {
  ok: "text-emerald-400",
  warn: "text-amber-300",
  error: "text-red-400",
  info: "text-zinc-300",
};

/** Live feed of what the CRE verifier does for this campaign / creator (read from the relayer's log). */
export function CreLogs({ vault, wallet }: { vault?: string | null; wallet?: string | null }) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [online, setOnline] = useState<boolean | null>(null);
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!vault || !wallet) return;
    let live = true;
    const load = async () => {
      try {
        const r = await fetch(`/api/cre-logs?vault=${vault}&wallet=${wallet}`, { cache: "no-store" });
        const j = (await r.json()) as { entries: Entry[]; online: boolean };
        if (live) {
          setEntries(j.entries);
          setOnline(j.online);
        }
      } catch {
        /* keep the last good view */
      }
    };
    queueMicrotask(() => void load());
    const t = setInterval(() => void load(), 4000);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, [vault, wallet]);

  useEffect(() => {
    const el = box.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [entries]);

  return (
    <div>
      <p className="mb-3 flex items-center gap-2 text-xs text-muted-foreground">
        <span className={`h-2 w-2 rounded-full ${online ? "bg-emerald-500" : "bg-zinc-400"}`} />
        {online ? "CRE verifier is running" : "No recent verifier activity"}
      </p>
      <div ref={box} className="h-64 overflow-y-auto rounded-2xl bg-zinc-950 p-4 font-mono text-xs leading-relaxed">
        {entries.length === 0 ? (
          <p className="text-zinc-500">Waiting for the verifier. Its steps will appear here.</p>
        ) : (
          entries.map((e, i) => (
            <div key={i} className={TONE[e.level] ?? TONE.info}>
              <span className="text-zinc-500">{new Date(e.t).toLocaleTimeString()} </span>
              {e.step && <span className="text-zinc-500">[{e.step}] </span>}
              {e.msg}
              {e.tx && (
                <>
                  {" "}
                  <a className="text-sky-400 underline" target="_blank" rel="noreferrer" href={`https://testnet.arcscan.app/tx/${e.tx}`}>
                    tx
                  </a>
                </>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
