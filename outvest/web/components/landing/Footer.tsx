import Link from "next/link";
import { Logo } from "@/components/Logo";

export function CtaFooter() {
  return (
    <>
      <section className="mx-auto w-full max-w-6xl px-6 pb-24">
        <div className="surface-peri rounded-[32px] px-8 py-16 text-center">
          <h2 className="text-balance text-4xl font-bold text-ink sm:text-5xl">Fund a campaign. Let the vault do the rest.</h2>
          <p className="mx-auto mt-4 max-w-lg text-muted-foreground">Sign in with email or Google and get a wallet in under a minute.</p>
          <Link href="/get-started" className="soft-shadow mt-8 inline-block rounded-xl bg-primary px-7 py-3 font-medium text-white transition hover:-translate-y-px">Get started</Link>
        </div>
      </section>
      <footer className="mx-auto flex w-full max-w-6xl flex-col items-center justify-between gap-4 border-t border-border px-6 py-8 text-sm text-muted-foreground sm:flex-row">
        <Logo />
        <p>Testnet preview. Not audited. Not financial advice.</p>
      </footer>
    </>
  );
}
