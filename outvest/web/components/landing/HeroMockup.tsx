import { Bot, Check, Lock, ShieldCheck, Timer, X } from "lucide-react";
import { cn } from "@/lib/utils";

const steps = ["Join", "Bind", "Snapshot", "Verify", "Paid"];

const rules = [
  { text: "Funds locked in the vault", ok: true },
  { text: "Pay only the bound wallet", ok: true },
  { text: "Cap of $300 per creator", ok: true },
  { text: "Release by any admin", ok: false },
];

const schedule = [
  { when: "Day 20", tag: "Drip", amt: "$15.80", tone: "bg-sky" },
  { when: "Day 30", tag: "50% unlocked", amt: "$100.00", tone: "bg-peach" },
  { when: "Day 60", tag: "80% unlocked", amt: "$153.60", tone: "bg-white" },
  { when: "Day 90", tag: "Final", amt: "$184.00", tone: "bg-white" },
];

export function HeroMockup() {
  return (
    <div className="relative mx-auto mt-24 h-[470px] w-full max-w-5xl">
      {/* left: campaign terms */}
      <div className="soft-shadow absolute left-0 top-10 hidden w-[380px] -rotate-[3deg] rounded-3xl bg-white p-6 md:block">
        <div className="flex items-center gap-3">
          <span className="grid size-9 place-items-center rounded-full bg-peri text-primary">
            <Bot className="size-4" />
          </span>
          <p className="text-lg font-semibold text-ink">Campaign vault</p>
        </div>
        <p className="mt-5 text-sm text-muted-foreground">Funded by</p>
        <div className="mt-1.5 flex items-center gap-3 rounded-xl border border-border p-3">
          <div className="flex -space-x-2">
            <span className="grid size-8 place-items-center rounded-full bg-muted text-xs font-medium ring-2 ring-white">AK</span>
            <span className="grid size-8 place-items-center rounded-full bg-peri text-xs font-medium ring-2 ring-white">M</span>
          </div>
          <p className="text-sm text-ink">Acme Co. · budget $1,000</p>
        </div>
        <p className="mt-5 text-sm text-muted-foreground">Rules the vault enforces</p>
        <ul className="mt-2 space-y-2.5">
          {rules.map((r) => (
            <li key={r.text} className="flex items-center gap-3 text-sm text-ink">
              <span className={cn("grid size-5 place-items-center rounded-md", r.ok ? "bg-ink text-white" : "border border-rust/40 text-rust")}>
                {r.ok ? <Check className="size-3.5" /> : <X className="size-3" />}
              </span>
              {r.text}
            </li>
          ))}
        </ul>
        <span className="mt-6 inline-block rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white">Lock funds</span>
      </div>

      {/* right: schedule */}
      <div className="soft-shadow absolute right-0 top-10 hidden w-[380px] rotate-[3deg] rounded-3xl bg-white p-6 md:block">
        <p className="text-right text-sm leading-snug text-muted-foreground">
          Payouts follow verified views,
          <br />
          then a fixed unlock schedule.
        </p>
        <ul className="mt-5 space-y-2.5">
          {schedule.map((s) => (
            <li key={s.when} className={cn("flex items-center justify-between rounded-xl border border-border px-4 py-3 text-sm", s.tone)}>
              <span className="font-medium text-ink">{s.when}</span>
              <span className="text-xs text-muted-foreground">{s.tag}</span>
              <span className="font-semibold text-ink">{s.amt}</span>
            </li>
          ))}
        </ul>
      </div>

      {/* center: report / claim */}
      <div className="soft-shadow absolute left-1/2 top-0 z-10 w-full max-w-[540px] -translate-x-1/2 overflow-hidden rounded-3xl bg-white">
        <div className="flex items-center justify-between border-b border-border px-6 py-4">
          <p className="font-semibold text-ink">New verified report</p>
          <span className="flex items-center gap-1.5 rounded-full bg-peach/70 px-3 py-1 text-xs font-semibold text-rust">
            <Timer className="size-3.5" /> 09:52
          </span>
        </div>
        <div className="flex">
          <ol className="hidden w-36 shrink-0 space-y-3.5 border-r border-border p-5 text-sm sm:block">
            {steps.map((s, i) => (
              <li key={s} className={cn("flex items-center gap-2.5", i === 3 ? "font-semibold text-ink" : "text-muted-foreground")}>
                <span className={cn("grid size-5 place-items-center rounded-full text-[11px]", i === 3 ? "bg-peri text-primary" : "bg-muted")}>{i + 1}</span>
                {s}
              </li>
            ))}
          </ol>
          <div className="flex-1 space-y-4 p-5 text-left">
            <Field label="Campaign">
              <div className="rounded-lg bg-peri px-3 py-2.5 text-sm text-ink">Spring launch review<span className="ml-0.5 animate-pulse">|</span></div>
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Views (lagged min)"><Box>48,200</Box></Field>
              <Field label="Source"><Box>YouTube Data API</Box></Field>
            </div>
            <Field label="Payee (bound to this video)">
              <div className="flex items-center gap-2 rounded-lg border border-border px-3 py-2.5 text-sm text-ink">
                <Lock className="size-3.5 text-muted-foreground" /> maya.outvest · 0x71C…9a2
              </div>
            </Field>
            <div className="rounded-xl bg-peri/60 p-4">
              <p className="text-xs text-muted-foreground">Claimable now</p>
              <div className="mt-1 flex items-end justify-between">
                <p className="text-3xl font-semibold tracking-tight text-ink">
                  $84 <span className="text-xs font-medium text-muted-foreground">USDC</span>
                </p>
                <span className="flex items-center gap-1 text-xs font-medium text-ok">
                  <ShieldCheck className="size-3.5" /> Within cap
                </span>
              </div>
            </div>
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-border px-5 py-3.5">
          <span className="rounded-lg bg-muted px-4 py-2 text-sm font-medium text-ink">View rules</span>
          <span className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white">Claim</span>
        </div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-1.5 text-xs font-medium text-ink">{label}</p>
      {children}
    </div>
  );
}
function Box({ children }: { children: React.ReactNode }) {
  return <div className="rounded-lg border border-border px-3 py-2.5 text-sm text-ink">{children}</div>;
}
