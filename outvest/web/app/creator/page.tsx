import { Check, Copy, Lock, Timer } from "lucide-react";
import { AppShell, Panel, ScheduleChart, Stat } from "@/components/app/AppShell";
import { cn } from "@/lib/utils";

const steps = [
  { t: "Joined campaign", done: true },
  { t: "Challenge code issued", done: true },
  { t: "Code found in video description", done: false, current: true },
  { t: "Wallet bound by verified report", done: false },
];

const history = [
  { d: "Nov 02", t: "Claim · Spring launch review", a: "+$84.00", tx: "0x7a3f…c91e" },
  { d: "Oct 18", t: "Claim · Spring launch review", a: "+$15.80", tx: "0x31de…a04b" },
];

export default function CreatorPage() {
  return (
    <AppShell role="creator">
      <div className="pt-6">
        <h1 className="text-4xl font-bold text-ink">Your earnings</h1>
        <p className="mt-2 text-muted-foreground">Pay follows verified views, then a fixed unlock schedule. It lands in your wallet automatically.</p>
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-3">
        <div className="surface-sky rounded-3xl p-6 sm:col-span-1">
          <p className="text-sm text-muted-foreground">Claimable now</p>
          <p className="mt-2 text-5xl font-semibold tracking-tight text-ink">$84 <span className="text-sm font-medium text-muted-foreground">USDC</span></p>
          <button className="soft-shadow mt-5 rounded-xl bg-primary px-5 py-2.5 text-sm font-medium text-white">Claim now</button>
        </div>
        <Stat tone="surface-lilac" label="Earned so far" value="$184" sub="Cap $300 per creator" />
        <Stat tone="surface-peach" label="Next unlock" value="Day 30" sub="in 9 days · 50% of earned" />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-5">
        <Panel title="Register your video" className="lg:col-span-3">
          <ol className="space-y-3">
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
          <p className="mb-1.5 mt-6 text-xs font-medium text-ink">Paste this code in your video description</p>
          <div className="flex items-center justify-between rounded-xl bg-peri/60 px-4 py-3 font-mono text-sm text-ink">
            outvest-9f3a1c42e8b7
            <Copy className="size-4 text-muted-foreground" />
          </div>
          <p className="mb-1.5 mt-5 text-xs font-medium text-ink">Payee (bound to this video)</p>
          <div className="flex items-center gap-2 rounded-lg border border-border px-3 py-2.5 text-sm text-ink">
            <Lock className="size-3.5 text-muted-foreground" /> 0x289f…0687
          </div>
        </Panel>

        <div className="space-y-6 lg:col-span-2">
          <Panel title="Unlock schedule"><ScheduleChart /></Panel>
          <Panel title="Payout history">
            <ul className="divide-y divide-border">
              {history.map((h) => (
                <li key={h.tx} className="flex items-center justify-between py-3 first:pt-0 last:pb-0">
                  <div>
                    <p className="text-sm font-medium text-ink">{h.t}</p>
                    <p className="font-mono text-xs text-muted-foreground">{h.d} · {h.tx}</p>
                  </div>
                  <span className="font-semibold text-ok">{h.a}</span>
                </li>
              ))}
            </ul>
          </Panel>
        </div>
      </div>
    </AppShell>
  );
}
