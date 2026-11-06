import Link from "next/link";
import { Bell, Copy } from "lucide-react";
import { Logo } from "@/components/Logo";
import { cn } from "@/lib/utils";

export function AppShell({ role, children }: { role: "brand" | "creator"; children: React.ReactNode }) {
  const tabs = [
    { href: "/brand", label: "Brand", active: role === "brand" },
    { href: "/creator", label: "Creator", active: role === "creator" },
  ];
  return (
    <div className="relative min-h-screen">
      <div className="dot-grid pointer-events-none absolute inset-x-0 top-0 h-[420px] opacity-60" aria-hidden />
      <header className="relative z-10 mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-5">
        <Logo />
        <nav className="soft-shadow flex rounded-xl bg-white p-1 text-sm font-medium">
          {tabs.map((t) => (
            <Link key={t.href} href={t.href} className={cn("rounded-lg px-4 py-1.5 transition", t.active ? "bg-ink text-white" : "text-ink/70 hover:text-ink")}>
              {t.label}
            </Link>
          ))}
        </nav>
        <div className="flex items-center gap-2">
          <span className="soft-shadow hidden items-center gap-2 rounded-xl bg-white px-3 py-2 font-mono text-xs text-ink sm:flex">
            <span className="size-2 rounded-full bg-ok" /> 0x289f…0687 <Copy className="size-3.5 text-muted-foreground" />
          </span>
          <span className="soft-shadow grid size-9 place-items-center rounded-xl bg-white text-ink"><Bell className="size-4" /></span>
        </div>
      </header>
      <main className="relative z-10 mx-auto w-full max-w-6xl px-6 pb-20">{children}</main>
    </div>
  );
}

export function Stat({ label, value, sub, tone }: { label: string; value: string; sub?: string; tone: string }) {
  return (
    <div className={cn("rounded-3xl p-6", tone)}>
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 text-4xl font-semibold tracking-tight text-ink">{value}</p>
      {sub && <p className="mt-1 text-xs text-muted-foreground">{sub}</p>}
    </div>
  );
}

export function Panel({ title, action, className, children }: { title: string; action?: React.ReactNode; className?: string; children: React.ReactNode }) {
  return (
    <section className={cn("soft-shadow rounded-3xl bg-white p-6", className)}>
      <div className="mb-5 flex items-center justify-between">
        <h2 className="text-xl font-semibold text-ink">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

export function ScheduleChart() {
  // f(t): 0% to day 7, linear to 20% by day 30 -> 50% at 30, 80% at 60, 100% at 90
  const pts: [number, number][] = [[0, 0], [7, 0], [30, 50], [60, 80], [90, 100]];
  const x = (d: number) => 20 + (d / 90) * 360;
  const y = (v: number) => 130 - (v / 100) * 110;
  const path = pts.map(([d, v], i) => `${i ? "L" : "M"}${x(d)},${y(v)}`).join(" ");
  return (
    <svg viewBox="0 0 400 150" className="w-full" role="img" aria-label="Unlock schedule: 0% until day 7, 50% at day 30, 80% at day 60, 100% at day 90">
      {[0, 50, 100].map((v) => (
        <g key={v}>
          <line x1="20" x2="380" y1={y(v)} y2={y(v)} className="stroke-ink/10" strokeDasharray="3 4" />
          <text x="0" y={y(v) + 3} className="fill-muted-foreground text-[9px]">{v}%</text>
        </g>
      ))}
      <path d={`${path} L${x(90)},${y(0)} L${x(0)},${y(0)} Z`} className="fill-primary/10" />
      <path d={path} fill="none" className="stroke-primary" strokeWidth="2.5" strokeLinejoin="round" />
      {pts.slice(1).map(([d, v]) => (
        <circle key={d} cx={x(d)} cy={y(v)} r="4" className="fill-white stroke-primary" strokeWidth="2" />
      ))}
      {[0, 30, 60, 90].map((d) => (
        <text key={d} x={x(d)} y="146" textAnchor="middle" className="fill-muted-foreground text-[9px]">Day {d}</text>
      ))}
    </svg>
  );
}
