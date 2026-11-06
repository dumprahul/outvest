import { ArrowUpRight, Plus, ShieldCheck } from "lucide-react";
import { AppShell, Panel, ScheduleChart, Stat } from "@/components/app/AppShell";
import { Progress } from "@/components/ui/progress";

const campaigns = [
  { name: "Spring launch review", budget: 1000, paid: 284, creators: 8, hash: "0x9f3a…c21e", status: "Live" },
  { name: "Summer unboxing push", budget: 2500, paid: 0, creators: 0, hash: "0x41b7…07d2", status: "Funding" },
  { name: "Q3 tutorial series", budget: 600, paid: 600, creators: 4, hash: "0xa0c9…55e1", status: "Settled" },
];

const fields = [
  ["Budget (USDC)", "1,000"],
  ["Rate per 1,000 views", "2.00"],
  ["Per-creator cap", "300"],
  ["Lag window", "7 days"],
];

export default function BrandPage() {
  return (
    <AppShell role="brand">
      <div className="flex flex-wrap items-end justify-between gap-4 pt-6">
        <div>
          <h1 className="text-4xl font-bold text-ink">Campaigns</h1>
          <p className="mt-2 text-muted-foreground">Funds are escrowed in each vault. You can&apos;t withdraw mid-campaign, and neither can we.</p>
        </div>
        <button className="soft-shadow flex items-center gap-2 rounded-xl bg-primary px-5 py-3 font-medium text-white transition hover:-translate-y-px">
          <Plus className="size-4" /> Create campaign
        </button>
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat tone="surface-sky" label="Locked in vaults" value="$4,100" sub="3 campaigns" />
        <Stat tone="surface-lilac" label="Paid to creators" value="$884" sub="All verified onchain" />
        <Stat tone="surface-peach" label="Active creators" value="12" sub="Across 2 live campaigns" />
        <Stat tone="surface-peri" label="Verified views" value="142.6k" sub="Lagged minimum" />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-5">
        <Panel title="Your campaigns" className="lg:col-span-3">
          <ul className="divide-y divide-border">
            {campaigns.map((c) => (
              <li key={c.name} className="py-4 first:pt-0 last:pb-0">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-semibold text-ink">{c.name}</p>
                    <p className="mt-0.5 flex items-center gap-1.5 font-mono text-xs text-muted-foreground">
                      <ShieldCheck className="size-3.5 text-ok" /> {c.hash} · {c.creators} creators
                    </p>
                  </div>
                  <span className="rounded-full bg-peri px-3 py-1 text-xs font-semibold text-primary">{c.status}</span>
                </div>
                <div className="mt-3 flex items-center gap-3">
                  <Progress value={(c.paid / c.budget) * 100} className="h-2 flex-1" />
                  <span className="shrink-0 text-sm text-ink">${c.paid} <span className="text-muted-foreground">/ ${c.budget}</span></span>
                  <ArrowUpRight className="size-4 shrink-0 text-muted-foreground" />
                </div>
              </li>
            ))}
          </ul>
        </Panel>

        <Panel title="New campaign" className="lg:col-span-2">
          <div className="grid grid-cols-2 gap-3">
            {fields.map(([l, v]) => (
              <div key={l}>
                <p className="mb-1.5 text-xs font-medium text-ink">{l}</p>
                <div className="rounded-lg border border-border px-3 py-2.5 text-sm text-ink">{v}</div>
              </div>
            ))}
          </div>
          <p className="mb-1 mt-6 text-xs font-medium text-ink">Unlock schedule</p>
          <ScheduleChart />
          <button className="mt-4 w-full rounded-xl bg-ink py-3 text-sm font-medium text-white">Review & lock funds</button>
          <p className="mt-3 text-center text-xs text-muted-foreground">Rules are hashed at creation and can never change.</p>
        </Panel>
      </div>
    </AppShell>
  );
}
