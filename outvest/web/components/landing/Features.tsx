import Link from "next/link";
import { Ban, CalendarClock, Check, ChevronDown, Link2, Lock, Mail, ShieldCheck, Timer, User, Video } from "lucide-react";
import { cn } from "@/lib/utils";

function CardShell({ id, tone, title, body, cta, href, className, children }: {
  id?: string; tone: string; title: string; body: string; cta?: string; href?: string; className?: string; children?: React.ReactNode;
}) {
  return (
    <article id={id} className={cn("relative flex min-h-[420px] scroll-mt-24 flex-col items-center overflow-hidden rounded-[28px] px-8 pt-10 text-center", tone, className)}>
      <h3 className="text-3xl font-semibold text-ink">{title}</h3>
      <p className="mt-4 max-w-sm text-[15px] leading-relaxed text-muted-foreground">{body}</p>
      {cta && (
        <Link href={href ?? "/get-started"} className="soft-shadow mt-6 rounded-xl bg-white px-5 py-2.5 text-[15px] font-medium text-ink transition hover:-translate-y-px">
          {cta}
        </Link>
      )}
      <div className="relative mt-auto w-full">{children}</div>
    </article>
  );
}

function OrbitChip({ Icon, className }: { Icon: typeof Video; className: string }) {
  return (
    <span className={cn("soft-shadow absolute grid size-12 place-items-center rounded-full bg-white text-primary", className)}>
      <Icon className="size-5" />
    </span>
  );
}

export function Features() {
  return (
    <section id="how-it-works" className="mx-auto w-full max-w-6xl scroll-mt-20 px-6 py-24">
      <div className="mx-auto max-w-3xl text-center">
        <h2 className="text-balance text-5xl font-bold leading-[1.05] text-ink sm:text-6xl">
          With OutVest, creator payouts are automatic
        </h2>
        <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground">
          Effortless campaigns for brands and the creators they back. Escrowed upfront, verified by views, released by
          the vault.
        </p>
      </div>

      <div className="mt-16 grid gap-5 md:grid-cols-5">
        <CardShell id="creators" tone="surface-sky" className="md:col-span-3" title="Verified by Chainlink" body="Public YouTube view counts are read by a decentralized oracle network and written onchain as signed reports. No screenshots, no trust." cta="See how it works" href="#rules">
          <div className="relative mx-auto h-[210px] w-[420px] max-w-full">
            <svg viewBox="0 0 420 210" className="absolute inset-0 size-full text-ink/15" fill="none" stroke="currentColor" aria-hidden>
              <circle cx="210" cy="250" r="230" /><circle cx="210" cy="250" r="170" /><circle cx="210" cy="250" r="110" />
            </svg>
            <span className="soft-shadow absolute bottom-10 left-1/2 -translate-x-1/2 rounded-xl bg-white px-6 py-2.5 text-lg font-semibold text-ink">OutVest</span>
            <OrbitChip Icon={Video} className="left-1/2 top-0 -translate-x-1/2" />
            <OrbitChip Icon={CalendarClock} className="left-[8%] top-[50px]" />
            <OrbitChip Icon={Mail} className="right-[8%] top-[60px]" />
            <OrbitChip Icon={Link2} className="bottom-2 right-[30%]" />
          </div>
        </CardShell>

        <CardShell tone="surface-lilac" className="md:col-span-2" title="Unlocks on a schedule" body="Each tranche is held in the vault and unlocks on a timetable fixed at creation." cta="Get started">
          <div className="relative mx-auto h-[190px] w-full max-w-[360px] overflow-hidden text-left">
            {[
              { t: "Tranche 3", sub: "Day 60 · $153.60", clock: "02:03", y: 120 },
              { t: "Tranche 2", sub: "Day 30 · $100.00", clock: "06:12", y: 66, rot: "-rotate-2" },
              { t: "Tranche 1", sub: "Day 20 · $15.80", clock: "09:41", y: 14, rot: "rotate-1" },
            ].map((c) => (
              <div key={c.t} style={{ top: c.y }} className={cn("soft-shadow absolute inset-x-0 rounded-2xl bg-white px-4 py-3", c.rot)}>
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold text-ink">{c.t}</p>
                  <span className="flex items-center gap-1 text-xs font-semibold text-rust"><Timer className="size-3.5" />{c.clock}</span>
                </div>
                <p className="text-xs text-muted-foreground">{c.sub}</p>
              </div>
            ))}
          </div>
        </CardShell>

        <CardShell id="brands" tone="surface-peach" className="md:col-span-2" title="Rules the vault enforces" body="It only pays the bound wallet, under the cap you set. Nobody holds an admin key.">
          <div className="mx-auto flex h-[200px] w-full max-w-[360px] flex-col items-center justify-end pb-6">
            <div className="flex w-full items-center justify-between">
              <Person label="Brand" />
              <span className="rounded-full border border-rust/30 bg-white/70 px-3 py-1 font-mono text-xs text-rust">payee-locked</span>
              <Person label="Creator" />
            </div>
            <div className="soft-shadow mt-8 flex items-center gap-5 rounded-2xl bg-white px-6 py-3 text-primary">
              <ShieldCheck className="size-5" /><Lock className="size-5" /><Check className="size-5" /><Ban className="size-5" />
            </div>
          </div>
        </CardShell>

        <CardShell tone="surface-peri" className="md:col-span-3" title="Paid by verified views" body="Pay per 1,000 verified views, measured on a lag and capped per creator. The vault does the math, onchain.">
          <div className="relative mx-auto h-[200px] w-full max-w-[460px]">
            {[
              { on: true, a: "Day 20", b: "$15.80", tag: "Drip", cls: "left-[8%] top-0 -rotate-6" },
              { on: false, a: "Day 30", b: "$100", tag: "Milestone", cls: "left-[26%] top-[62px] -rotate-3" },
              { on: false, a: "Day 90", b: "$184", tag: "Final", cls: "left-[20%] top-[130px]" },
            ].map((r) => (
              <div key={r.a} className={cn("soft-shadow absolute flex items-center gap-3 rounded-2xl bg-white px-4 py-3", r.cls)}>
                <span className={cn("flex h-5 w-9 items-center rounded-full p-0.5", r.on ? "justify-end bg-primary" : "justify-start bg-muted")}>
                  <span className="size-4 rounded-full bg-white shadow" />
                </span>
                <span className="rounded-lg border border-border px-3 py-1 text-sm text-ink">{r.a}</span>
                <span className="text-muted-foreground">→</span>
                <span className="rounded-lg border border-border px-3 py-1 text-sm font-semibold text-ink">{r.b}</span>
                <span className="text-xs font-medium text-muted-foreground">{r.tag}</span>
              </div>
            ))}
          </div>
        </CardShell>
      </div>
    </section>
  );
}

function Person({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center gap-2">
      <span className="grid size-16 place-items-center rounded-full bg-white text-rust soft-shadow"><User className="size-7" /></span>
      <span className="text-sm text-ink">{label}</span>
    </div>
  );
}

export function AllPurpose() {
  const chips = ["Lag 7 days", "Cap $300", "Ratchet", "Auto-pause"];
  const selects = [["Lag window", "7 days"], ["Minimum drip cap", "25%"], ["Dead-man timeout", "30 days"]];
  return (
    <section id="rules" className="mx-auto w-full max-w-6xl scroll-mt-20 px-6 pb-24">
      <h2 className="text-center text-5xl font-bold leading-[1.05] text-ink sm:text-6xl">Your all-purpose payout app</h2>

      <div className="mt-14 grid gap-5 md:grid-cols-5">
        <article className="surface-sky relative min-h-[300px] overflow-hidden rounded-[28px] p-8 md:col-span-3">
          <h3 className="text-3xl font-semibold text-ink">Avoid fraud exposure</h3>
          <p className="mt-3 max-w-md text-[15px] leading-relaxed text-muted-foreground">Lag windows, per-creator caps and automatic pause blunt view botting before money moves.</p>
          <Link href="/get-started" className="soft-shadow mt-6 inline-block rounded-xl bg-white px-5 py-2.5 font-medium text-ink">Get started</Link>
          <div className="mt-10 flex flex-wrap gap-3">
            {chips.map((c, i) => (
              <span key={c} className={cn("soft-shadow rounded-xl px-4 py-2 text-sm font-medium", i === 3 ? "bg-primary text-white" : "bg-white text-ink")}>{c}</span>
            ))}
          </div>
        </article>

        <article className="surface-lilac relative min-h-[300px] overflow-hidden rounded-[28px] p-8 md:col-span-2">
          <h3 className="text-3xl font-semibold text-ink">Receipts without chasing</h3>
          <p className="mt-3 max-w-xs text-[15px] leading-relaxed text-muted-foreground">Every payout is onchain, with the transaction hash as proof.</p>
          <div className="soft-shadow absolute inset-x-8 bottom-8 flex items-center gap-3 rounded-2xl bg-white p-3.5">
            <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-ink text-white"><Mail className="size-5" /></span>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-ink">Receipt: Spring launch · $84.00 USDC</p>
              <p className="truncate text-xs text-muted-foreground">Settled on Arc · tx 0x7a3f…c91e</p>
            </div>
          </div>
        </article>

        <article className="relative min-h-[300px] rounded-[28px] bg-white p-8 soft-shadow md:col-span-2">
          <h3 className="text-2xl font-semibold text-ink">Lag and limits</h3>
          <div className="mt-6 space-y-4">
            {selects.map(([l, v]) => (
              <div key={l}>
                <p className="mb-1.5 text-sm font-medium text-ink">{l}</p>
                <div className="flex items-center justify-between rounded-xl border border-border px-4 py-2.5 text-sm text-ink">
                  {v}<ChevronDown className="size-4 text-muted-foreground" />
                </div>
              </div>
            ))}
          </div>
        </article>

        <article className="surface-peach relative min-h-[300px] overflow-hidden rounded-[28px] p-8 md:col-span-3">
          <h3 className="text-3xl font-semibold text-ink">Public rules, checkable by anyone</h3>
          <p className="mt-3 max-w-md text-[15px] leading-relaxed text-muted-foreground">Every parameter is hashed at creation. Brands, creators and the public can verify the rules never changed.</p>
          <div className="soft-shadow absolute inset-x-8 bottom-8 flex items-center justify-between rounded-2xl bg-white p-4">
            <div className="flex items-center gap-3">
              <span className="grid size-11 place-items-center rounded-full bg-gradient-to-br from-peach to-[#e58f7e] text-sm font-semibold text-white">SL</span>
              <div>
                <p className="font-semibold text-ink">Spring launch review</p>
                <p className="text-sm text-muted-foreground">$1,000 budget · $2 / 1k views</p>
              </div>
            </div>
            <div className="text-right">
              <p className="text-xs text-muted-foreground">Rule hash</p>
              <p className="flex items-center justify-end gap-1.5 font-mono text-sm text-ink"><ShieldCheck className="size-4 text-ok" />0x9f3a…c21e</p>
            </div>
          </div>
        </article>
      </div>
    </section>
  );
}
