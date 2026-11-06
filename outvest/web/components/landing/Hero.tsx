import Link from "next/link";
import { ArrowRight, CalendarClock, FileText, Link2, ShieldCheck, Timer, Video, Wallet } from "lucide-react";
import ShinyText from "@/components/ShinyText";
import { HeroMockup } from "./HeroMockup";

const chips = [
  { Icon: Wallet, cls: "right-[18%] top-24 text-primary float-slow" },
  { Icon: Video, cls: "right-[4%] top-[300px] text-[#3a9cb8] float-slower" },
  { Icon: CalendarClock, cls: "left-[6%] top-[400px] text-primary float-slow" },
  { Icon: Timer, cls: "left-[1%] top-[520px] text-rust float-slower" },
  { Icon: FileText, cls: "left-[14%] top-[620px] text-rust float-slow hidden lg:grid" },
  { Icon: Link2, cls: "right-[2%] top-[500px] text-primary float-slow" },
  { Icon: ShieldCheck, cls: "right-[10%] top-[640px] text-primary float-slower hidden lg:grid" },
];

export function Hero() {
  return (
    <section className="relative overflow-hidden pb-24">
      <div className="dot-grid pointer-events-none absolute inset-0 -z-0 opacity-70" aria-hidden />
      <div className="pointer-events-none absolute inset-y-0 left-[12%] hidden border-l border-dashed border-ink/10 lg:block" aria-hidden />
      <div className="pointer-events-none absolute inset-y-0 right-[12%] hidden border-r border-dashed border-ink/10 lg:block" aria-hidden />

      {chips.map(({ Icon, cls }, i) => (
        <span key={i} className={`soft-shadow absolute z-10 hidden size-[68px] place-items-center rounded-2xl bg-white md:grid ${cls}`} aria-hidden>
          <Icon className="size-6" />
        </span>
      ))}

      <div className="relative z-10 mx-auto max-w-4xl px-6 pt-20 text-center">
        <span className="soft-shadow inline-flex items-center gap-2 rounded-full bg-white px-4 py-2 text-sm font-medium text-ink/80">
          <span className="size-2 rounded-full bg-primary" />
          <ShinyText text="Views verified. USDC released." speed={4} color="#4b4f6b" shineColor="#6c6bbd" />
        </span>
        <h1 className="mt-8 text-balance text-5xl font-bold leading-[1.02] text-ink sm:text-7xl">
          The better way to pay creators
        </h1>
        <p className="mx-auto mt-7 max-w-2xl text-lg leading-relaxed text-muted-foreground">
          Brands lock USDC in a campaign vault. Chainlink verifies public YouTube views and the vault releases pay on a
          fixed schedule. Within rules nobody can change.
        </p>
        <div className="mt-9 flex items-center justify-center gap-5">
          <Link href="/get-started" className="soft-shadow rounded-xl bg-white px-6 py-3 font-medium text-ink transition hover:-translate-y-px">
            Get started
          </Link>
          <a href="#how-it-works" className="flex items-center gap-1.5 font-medium text-ink/80 hover:text-ink">
            See how it works <ArrowRight className="size-4" />
          </a>
        </div>
      </div>

      <div className="relative z-10 px-6">
        <HeroMockup />
      </div>
    </section>
  );
}
