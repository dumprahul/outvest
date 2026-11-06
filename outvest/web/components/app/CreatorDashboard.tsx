"use client";

import Link from "next/link";
import { CreLogs } from "@/components/app/CreLogs";
import { useCallback, useEffect, useState } from "react";
import { Check, Copy, Loader2, Lock, Timer } from "lucide-react";
import { Panel, ScheduleChart, Stat } from "@/components/app/AppShell";
import { useWallet } from "@/components/WalletProvider";
import {
  RECEIPT_DST_SELECTOR, RECEIPT_RECEIVER, RECEIPT_SENDER, baseSepolia, basePublicClient, bytes32ToVideoId,
  explorerAddress, fmtUsdc, loadCampaigns, publicClient, receiptReceiverAbi, receiptSenderAbi, vaultAbi,
  videoIdToBytes32, type CampaignView,
} from "@/lib/contracts";
import { cn } from "@/lib/utils";
import type { Hex } from "viem";

const ZERO32 = `0x${"0".repeat(64)}`;
const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const msgOf = (e: unknown) => (e instanceof Error ? e.message : String(e));
const input = "w-full rounded-lg border border-border px-3 py-2.5 text-sm text-ink outline-none focus:border-primary";

interface Me {
  pendingVideo: string | null;
  challenge: Hex | null;
  submitted: boolean;
  bound: boolean;
  paid: bigint;
  remaining: bigint;
  videos: string[];
  claimable: bigint;
}

async function loadMe(vault: Hex, wallet: Hex): Promise<Me> {
  const r = <T,>(fn: string, args: unknown[]) =>
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: fn, args } as never) as Promise<T>;
  const [pending, info, videos, claimable] = await Promise.all([
    r<readonly [Hex, Hex, bigint, bigint, number]>("pendingBinding", [wallet]),
    r<{ bound: boolean; paid: bigint; remaining: bigint }>("creatorInfo", [wallet]),
    r<readonly Hex[]>("videosOf", [wallet]),
    r<bigint>("claimable", [wallet]),
  ]);
  return {
    pendingVideo: pending[1] === ZERO32 ? null : bytes32ToVideoId(pending[0]),
    challenge: pending[1] === ZERO32 ? null : pending[1],
    submitted: pending[3] > 0n,
    bound: info.bound,
    paid: info.paid,
    remaining: info.remaining,
    videos: videos.map((v) => bytes32ToVideoId(v) ?? v),
    claimable,
  };
}

export function CreatorDashboard() {
  const w = useWallet();
  const [campaigns, setCampaigns] = useState<CampaignView[]>([]);
  const [vault, setVault] = useState<Hex | null>(null);
  const [me, setMe] = useState<Me | null>(null);
  const [videoId, setVideoId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const wallet = w.wallet?.address as Hex | undefined;
  const ready = w.step === "ready" && !!wallet;

  useEffect(() => {
    if (!ready) return;
    loadCampaigns()
      .then((all) => {
        const open = all.filter((c) => !c.finalized);
        setCampaigns(open);
        setVault((v) => v ?? open[0]?.vault ?? null);
      })
      .catch((e) => setError(msgOf(e)));
  }, [ready]);

  const refresh = useCallback(async () => {
    if (!vault || !wallet) return;
    try {
      setMe(await loadMe(vault, wallet));
    } catch (e) {
      setError(msgOf(e));
    }
  }, [vault, wallet]);

  // Initial load, then poll while a verification is in flight.
  useEffect(() => {
    queueMicrotask(() => void refresh());
    const t = setInterval(() => void refresh(), 8000);
    return () => clearInterval(t);
  }, [refresh]);

  async function run(fn: () => Promise<void>) {
    setError(null);
    setBusy(true);
    try {
      await fn();
      await new Promise((r) => setTimeout(r, 4000));
      await refresh();
      await w.refreshBalance();
    } catch (e) {
      setError(msgOf(e));
    } finally {
      setBusy(false);
    }
  }

  const requestBinding = () => run(() => w.sendTx(vault!, "requestBinding(bytes32)", [videoIdToBytes32(videoId.trim())]));
  const submit = () => run(() => w.sendTx(vault!, "submitForVerification()", []));
  const claim = () => run(() => w.sendTx(vault!, "claim(address)", [wallet!]));

  // Cross-chain receipt: Arc vault state -> CCIP -> Base Sepolia.
  const [receipt, setReceipt] = useState<bigint | null>(null);
  const [receiptNote, setReceiptNote] = useState<string | null>(null);
  const loadReceipt = useCallback(async () => {
    if (!RECEIPT_RECEIVER || !vault || !wallet) return;
    try {
      const r = await basePublicClient.readContract({
        address: RECEIPT_RECEIVER, abi: receiptReceiverAbi, functionName: "receipts", args: [wallet, vault],
      });
      setReceipt(r[3] === 0n ? null : r[0]);
    } catch {
      setReceipt(null);
    }
  }, [vault, wallet]);
  useEffect(() => {
    queueMicrotask(() => void loadReceipt());
  }, [loadReceipt]);

  async function sendReceipt() {
    setError(null);
    setReceiptNote(null);
    setBusy(true);
    try {
      const fee = await publicClient.readContract({
        address: RECEIPT_SENDER, abi: receiptSenderAbi, functionName: "quote",
        args: [BigInt(RECEIPT_DST_SELECTOR), RECEIPT_RECEIVER, vault!, wallet!],
      });
      // 30% headroom for fee drift; the sender refunds whatever is not used.
      const value = (Number(fee) / 1e18) * 1.3;
      await w.sendTx(RECEIPT_SENDER, "sendReceipt(uint64,address,address,address)",
        [RECEIPT_DST_SELECTOR, RECEIPT_RECEIVER, vault!, wallet!], value.toFixed(6));
      setReceiptNote("Sent. CCIP usually delivers within a few minutes; this updates by itself.");
      for (let i = 0; i < 40; i++) {
        await new Promise((r) => setTimeout(r, 15000));
        await loadReceipt();
      }
    } catch (e) {
      setError(msgOf(e));
    } finally {
      setBusy(false);
    }
  }

  if (!ready) {
    return (
      <div className="soft-shadow mt-8 rounded-3xl bg-white p-8 text-center">
        <p className="text-lg font-semibold text-ink">Sign in to join a campaign</p>
        <p className="mt-1 text-sm text-muted-foreground">Your wallet is where verified earnings are paid.</p>
        <Link href="/get-started" className="soft-shadow mt-5 inline-block rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white">
          {w.step === "loading" ? "Loading…" : "Get started"}
        </Link>
      </div>
    );
  }

  const camp = campaigns.find((c) => c.vault === vault);
  const steps = [
    { t: "Pick a campaign and enter your video", done: !!me?.challenge || !!me?.bound },
    { t: "Challenge code issued", done: !!me?.challenge || !!me?.bound },
    { t: "Code found in video description", done: !!me?.bound, current: !!me?.submitted && !me?.bound },
    { t: "Wallet bound and first payment sent", done: !!me?.bound },
  ];
  const earned = me ? me.paid : 0n;

  return (
    <>
      <div className="mt-8 grid gap-4 sm:grid-cols-3">
        <div className="surface-sky rounded-3xl p-6 sm:col-span-1">
          <p className="text-sm text-muted-foreground">Claimable now</p>
          <p className="mt-2 text-5xl font-semibold tracking-tight text-ink">
            ${fmtUsdc(me?.claimable ?? 0n)} <span className="text-sm font-medium text-muted-foreground">USDC</span>
          </p>
          <button
            disabled={busy || !me?.bound || (me?.claimable ?? 0n) === 0n}
            onClick={claim}
            className="soft-shadow mt-5 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white disabled:opacity-50"
          >
            Claim now
          </button>
        </div>
        <Stat tone="surface-lilac" label="Paid so far" value={`$${fmtUsdc(earned)}`} sub={camp ? `Cap $${fmtUsdc(camp.cap)} per creator` : "Pick a campaign"} />
        <Stat tone="surface-peach" label="Still reserved for you" value={`$${fmtUsdc(me?.remaining ?? 0n)}`} sub="Released by views and the schedule" />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-5">
        <Panel title="Register your video" className="lg:col-span-3">
          {campaigns.length === 0 ? (
            <p className="text-sm text-muted-foreground">No open campaigns yet. Ask a brand to create one.</p>
          ) : (
            <>
              <label className="text-xs font-medium text-ink">Campaign
                <select className={`${input} mt-1.5`} value={vault ?? ""} onChange={(e) => setVault(e.target.value as Hex)}>
                  {campaigns.map((c) => (
                    <option key={c.vault} value={c.vault}>
                      {short(c.vault)} · ${fmtUsdc(c.rate)}/1k views · cap ${fmtUsdc(c.cap)}
                    </option>
                  ))}
                </select>
              </label>

              <ol className="mt-5 space-y-3">
                {steps.map((s) => (
                  <li key={s.t} className="flex items-center gap-3 text-sm">
                    <span className={cn("grid size-6 place-items-center rounded-full text-xs", s.done ? "bg-ink text-white" : s.current ? "bg-peri text-primary ring-2 ring-primary/30" : "bg-muted text-muted-foreground")}>
                      {s.done ? <Check className="size-3.5" /> : ""}
                    </span>
                    <span className={cn(s.done || s.current ? "font-medium text-ink" : "text-muted-foreground")}>{s.t}</span>
                    {s.current && <span className="ml-auto flex items-center gap-1 text-xs font-semibold text-rust"><Timer className="size-3.5" />Checking</span>}
                  </li>
                ))}
              </ol>

              {!me?.bound && (
                <div className="mt-6">
                  <label className="text-xs font-medium text-ink">YouTube video id (the 11 characters after v=)
                    <input className={`${input} mt-1.5 font-mono`} placeholder="dQw4w9WgXcQ" value={videoId} onChange={(e) => setVideoId(e.target.value)} />
                  </label>
                  <button disabled={busy || videoId.trim().length !== 11} onClick={requestBinding} className="mt-3 rounded-xl bg-ink px-4 py-2.5 text-sm font-medium text-white disabled:opacity-50">
                    {me?.challenge ? "Get a new code" : "Get my code"}
                  </button>
                </div>
              )}

              {me?.challenge && !me.bound && (
                <>
                  <p className="mb-1.5 mt-6 text-xs font-medium text-ink">
                    Paste this code in the description of {me.pendingVideo ?? "your video"}, then press verify
                  </p>
                  <button
                    onClick={() => { void navigator.clipboard?.writeText(me.challenge!); setCopied(true); setTimeout(() => setCopied(false), 1500); }}
                    className="flex w-full items-center justify-between gap-3 rounded-xl bg-peri/60 px-4 py-3 text-left font-mono text-xs text-ink break-all"
                  >
                    {me.challenge}
                    {copied ? <Check className="size-4 shrink-0 text-ok" /> : <Copy className="size-4 shrink-0 text-muted-foreground" />}
                  </button>
                  <button disabled={busy} onClick={submit} className="soft-shadow mt-3 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white disabled:opacity-50">
                    {me.submitted ? "Verify again" : "I pasted it, verify"}
                  </button>
                  {me.submitted && <p className="mt-2 text-xs text-muted-foreground">Submitted. The verifier checks YouTube and binds your wallet; this page updates on its own.</p>}
                </>
              )}

              {me?.bound && (
                <p className="mt-6 rounded-xl bg-peri/60 px-4 py-3 text-sm text-ink">
                  Verified. Video {me.videos.join(", ")} is bound to your wallet and your first payment has been sent.
                </p>
              )}
            </>
          )}
          {busy && <p className="mt-4 flex items-center gap-2 text-xs text-muted-foreground"><Loader2 className="size-3.5 animate-spin" /> Confirm in the Circle window, then wait a few seconds…</p>}
          {error && <p className="mt-4 text-xs text-rust" role="alert">{error}</p>}
          <p className="mb-1.5 mt-6 text-xs font-medium text-ink">Payee (bound to this video)</p>
          <div className="flex items-center gap-2 rounded-lg border border-border px-3 py-2.5 text-sm text-ink">
            <Lock className="size-3.5 text-muted-foreground" /> {wallet && short(wallet)}
          </div>
        </Panel>

        <div className="space-y-6 lg:col-span-2">
          <Panel title="Unlock schedule"><ScheduleChart /></Panel>
          {RECEIPT_SENDER && RECEIPT_RECEIVER && me?.bound && (
            <Panel title="Portable earnings receipt">
              <p className="text-xs text-muted-foreground">
                Prove what you earned on another chain. A Chainlink CCIP message copies your payout total from Arc to {baseSepolia.name}.
              </p>
              <p className="mt-3 text-sm text-ink">
                On {baseSepolia.name}: <span className="font-semibold">{receipt === null ? "no receipt yet" : `$${fmtUsdc(receipt)} verified`}</span>
              </p>
              <button disabled={busy} onClick={sendReceipt} className="mt-3 rounded-xl bg-ink px-4 py-2.5 text-sm font-medium text-white disabled:opacity-50">
                {receipt === null ? "Send receipt to Base" : "Update receipt"}
              </button>
              {receiptNote && <p className="mt-2 text-xs text-muted-foreground">{receiptNote}</p>}
              <a className="mt-3 block text-xs text-primary underline" target="_blank" rel="noreferrer" href={`https://ccip.chain.link/address/${wallet}`}>Track on the CCIP explorer</a>
            </Panel>
          )}
          <Panel title="CRE activity">
            <CreLogs vault={vault} wallet={wallet} />
          </Panel>
          {camp && (
            <Panel title="Campaign vault">
              <a className="font-mono text-xs text-primary underline" href={explorerAddress(camp.vault)} target="_blank" rel="noreferrer">{camp.vault}</a>
              <p className="mt-2 text-xs text-muted-foreground">{camp.creatorCount.toString()}/{camp.maxCreators} creators · ${fmtUsdc(camp.totalFunded)} locked</p>
            </Panel>
          )}
        </div>
      </div>
    </>
  );
}
