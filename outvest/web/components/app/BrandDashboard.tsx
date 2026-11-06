"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ArrowUpRight, Loader2, Plus, ShieldCheck } from "lucide-react";
import { Panel, ScheduleChart, Stat } from "@/components/app/AppShell";
import { Progress } from "@/components/ui/progress";
import { useWallet } from "@/components/WalletProvider";
import {
  FACTORY, USDC, explorerAddress, factoryAbi, fmtUsdc, loadCampaigns, publicClient, toUnits, vaultAbi,
  type CampaignView,
} from "@/lib/contracts";
import type { Hex } from "viem";

const DAY = 86_400;
const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const msgOf = (e: unknown) => (e instanceof Error ? e.message : String(e));
const input = "w-full rounded-lg border border-border px-3 py-2.5 text-sm text-ink outline-none focus:border-primary";

/** Demo schedule: 25% at day 0, 50% at 30, 80% at 60, 100% at 90 (matches the deployed default). */
const SCHEDULE = [
  [0, 250_000, 500_000],
  [30 * DAY, 500_000, 800_000],
  [60 * DAY, 800_000, 1_000_000],
  [90 * DAY, 1_000_000, 1_000_000],
];

export function BrandDashboard() {
  const w = useWallet();
  const [campaigns, setCampaigns] = useState<CampaignView[]>([]);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ rate: "2", cap: "5", creators: "2" });
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const me = w.wallet?.address.toLowerCase();

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const all = await loadCampaigns();
      setCampaigns(all.filter((c) => c.brand.toLowerCase() === me));
    } catch (e) {
      setError(msgOf(e));
    } finally {
      setLoading(false);
    }
  }, [me]);

  useEffect(() => {
    if (w.step === "ready" && me) queueMicrotask(() => void refresh());
  }, [w.step, me, refresh]);

  /** Wait until the factory reports one more campaign than before (tx confirmed). */
  async function waitForNewCampaign(before: bigint): Promise<Hex> {
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 3000));
      const n = await publicClient.readContract({ address: FACTORY, abi: factoryAbi, functionName: "campaignCount" });
      if (n > before) {
        return (await publicClient.readContract({ address: FACTORY, abi: factoryAbi, functionName: "campaignAt", args: [n - 1n] })) as Hex;
      }
    }
    throw new Error("Campaign transaction not confirmed yet. Check the explorer and refresh.");
  }

  async function waitForFunding(vault: Hex, atLeast: bigint) {
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 3000));
      const funded = (await publicClient.readContract({
        address: vault, abi: vaultAbi, functionName: "totalFunded",
      })) as bigint;
      if (funded >= atLeast) return;
    }
    throw new Error("Funding not confirmed yet. Refresh in a moment.");
  }

  async function fundVault(vault: Hex, amount: bigint) {
    setStatus("Step 2 of 3 · Approve USDC (confirm with your PIN)");
    await w.sendTx(USDC, "approve(address,uint256)", [vault, amount.toString()]);
    // Allowance must be live before fund() or the transfer reverts.
    await new Promise((r) => setTimeout(r, 6000));
    setStatus("Step 3 of 3 · Lock funds in the vault (confirm with your PIN)");
    await w.sendTx(vault, "fund(uint256)", [amount.toString()]);
  }

  async function create() {
    setError(null);
    setBusy(true);
    try {
      if (!w.wallet) throw new Error("Wallet is not ready");
      if (!FACTORY) throw new Error("NEXT_PUBLIC_FACTORY is not set");
      const rate = Number(form.rate), cap = Number(form.cap), creators = Math.floor(Number(form.creators));
      if (!(rate > 0 && cap > 0 && creators >= 1 && creators <= 100)) throw new Error("Enter a positive rate, cap and creator count");
      const capU = toUnits(cap);
      const budget = capU * BigInt(creators);
      if (toUnits(Number(w.usdc)) < budget) throw new Error(`Not enough USDC. Need ${fmtUsdc(budget)}, wallet has ${w.usdc}`);

      const before = await publicClient.readContract({ address: FACTORY, abi: factoryAbi, functionName: "campaignCount" });
      const minPayout = capU / 10n > 1_000_000n ? 1_000_000n : capU / 10n;
      const deadline = Math.floor(Date.now() / 1000) + 30 * DAY;
      const params = [
        w.wallet.address, USDC, String(deadline), toUnits(rate).toString(), capU.toString(), String(creators),
        "3", "3600", "200000", String(3 * DAY), String(30 * DAY), minPayout.toString(), "100000",
        SCHEDULE.map((s) => s.map(String)),
      ];
      setStatus("Step 1 of 3 · Create the campaign (confirm with your PIN)");
      await w.sendTx(
        FACTORY,
        "createCampaign((address,address,uint64,uint256,uint256,uint32,uint8,uint32,uint64,uint64,uint64,uint256,uint32,(uint32,uint32,uint32)[]))",
        [params],
      );
      setStatus("Waiting for the campaign to confirm onchain…");
      const vault = await waitForNewCampaign(before);
      await fundVault(vault, budget);
      setStatus("Waiting for funding to confirm…");
      await waitForFunding(vault, budget);
      setStatus("Done. Your campaign is live and funded.");
      await w.refreshBalance();
      await refresh();
    } catch (e) {
      setError(msgOf(e));
      setStatus(null);
    } finally {
      setBusy(false);
    }
  }

  async function topUp(c: CampaignView) {
    setError(null);
    setBusy(true);
    try {
      const missing = c.cap * BigInt(c.maxCreators) - c.totalFunded;
      if (missing <= 0n) return;
      await fundVault(c.vault, missing);
      await waitForFunding(c.vault, c.totalFunded + missing);
      setStatus("Funded.");
      await w.refreshBalance();
      await refresh();
    } catch (e) {
      setError(msgOf(e));
    } finally {
      setBusy(false);
    }
  }

  if (w.step !== "ready") {
    return (
      <div className="soft-shadow mt-8 rounded-3xl bg-white p-8 text-center">
        <p className="text-lg font-semibold text-ink">Sign in to manage campaigns</p>
        <p className="mt-1 text-sm text-muted-foreground">You need your OutVest wallet to create and fund a campaign.</p>
        <Link href="/get-started" className="soft-shadow mt-5 inline-block rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white">
          {w.step === "loading" ? "Loading…" : "Get started"}
        </Link>
      </div>
    );
  }

  const locked = campaigns.reduce((a, c) => a + c.totalFunded, 0n);
  const paid = campaigns.reduce((a, c) => a + c.totalPaid, 0n);
  const creators = campaigns.reduce((a, c) => a + c.creatorCount, 0n);
  const budget = toUnits(Number(form.cap) || 0) * BigInt(Math.max(0, Math.floor(Number(form.creators) || 0)));

  return (
    <>
      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat tone="surface-sky" label="Locked in vaults" value={`$${fmtUsdc(locked)}`} sub={`${campaigns.length} campaigns`} />
        <Stat tone="surface-lilac" label="Paid to creators" value={`$${fmtUsdc(paid)}`} sub="Settled onchain" />
        <Stat tone="surface-peach" label="Bound creators" value={creators.toString()} sub="Across your campaigns" />
        <Stat tone="surface-peri" label="Wallet balance" value={`$${Number(w.usdc).toFixed(2)}`} sub="USDC on Arc Testnet" />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-5">
        <Panel
          title="Your campaigns"
          className="lg:col-span-3"
          action={<button onClick={refresh} className="text-xs font-medium text-primary">{loading ? "Loading…" : "Refresh"}</button>}
        >
          {campaigns.length === 0 ? (
            <p className="text-sm text-muted-foreground">{loading ? "Loading campaigns…" : "No campaigns yet. Create your first one."}</p>
          ) : (
            <ul className="divide-y divide-border">
              {campaigns.map((c) => {
                const target = c.cap * BigInt(c.maxCreators);
                const underfunded = c.totalFunded < target;
                return (
                  <li key={c.vault} className="py-4 first:pt-0 last:pb-0">
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <p className="font-semibold text-ink">Campaign {short(c.vault)}</p>
                        <p className="mt-0.5 flex items-center gap-1.5 font-mono text-xs text-muted-foreground">
                          <ShieldCheck className="size-3.5 text-ok" /> {c.creatorCount.toString()}/{c.maxCreators} creators · ${fmtUsdc(c.rate)} per 1k views
                        </p>
                      </div>
                      <span className="rounded-full bg-peri px-3 py-1 text-xs font-semibold text-primary">
                        {c.finalized ? "Settled" : underfunded ? "Needs funding" : "Live"}
                      </span>
                    </div>
                    <div className="mt-3 flex items-center gap-3">
                      <Progress value={target > 0n ? Number((c.totalPaid * 100n) / target) : 0} className="h-2 flex-1" />
                      <span className="shrink-0 text-sm text-ink">
                        ${fmtUsdc(c.totalPaid)} <span className="text-muted-foreground">/ ${fmtUsdc(target)}</span>
                      </span>
                      <a href={explorerAddress(c.vault)} target="_blank" rel="noreferrer" aria-label="View on explorer">
                        <ArrowUpRight className="size-4 shrink-0 text-muted-foreground" />
                      </a>
                    </div>
                    {underfunded && (
                      <button disabled={busy} onClick={() => topUp(c)} className="mt-3 rounded-lg bg-ink px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50">
                        Fund remaining ${fmtUsdc(target - c.totalFunded)}
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </Panel>

        <Panel title="New campaign" className="lg:col-span-2">
          <div className="grid grid-cols-2 gap-3">
            <label className="text-xs font-medium text-ink">Rate per 1,000 views (USDC)
              <input className={`${input} mt-1.5`} inputMode="decimal" value={form.rate} onChange={(e) => setForm({ ...form, rate: e.target.value })} />
            </label>
            <label className="text-xs font-medium text-ink">Per-creator cap (USDC)
              <input className={`${input} mt-1.5`} inputMode="decimal" value={form.cap} onChange={(e) => setForm({ ...form, cap: e.target.value })} />
            </label>
            <label className="text-xs font-medium text-ink">Max creators
              <input className={`${input} mt-1.5`} inputMode="numeric" value={form.creators} onChange={(e) => setForm({ ...form, creators: e.target.value })} />
            </label>
            <div className="text-xs font-medium text-ink">Total to lock
              <div className="mt-1.5 rounded-lg bg-peri/60 px-3 py-2.5 text-sm text-ink">${fmtUsdc(budget)}</div>
            </div>
          </div>
          <p className="mb-1 mt-6 text-xs font-medium text-ink">Unlock schedule (10% paid instantly when a creator is verified)</p>
          <ScheduleChart />
          <button
            disabled={busy}
            onClick={create}
            className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-ink py-3 text-sm font-medium text-white disabled:opacity-60"
          >
            {busy ? <Loader2 className="size-4 animate-spin" /> : <Plus className="size-4" />} Create & lock funds
          </button>
          {status && <p className="mt-3 text-center text-xs text-ink">{status}</p>}
          {error && <p className="mt-3 text-center text-xs text-rust" role="alert">{error}</p>}
          <p className="mt-3 text-center text-xs text-muted-foreground">Rules are hashed at creation and can never change. Takes 3 PIN confirmations.</p>
        </Panel>
      </div>
    </>
  );
}
