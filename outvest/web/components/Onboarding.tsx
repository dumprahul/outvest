"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Check, Copy, RefreshCw } from "lucide-react";
import { useCircleWallet, type Step } from "@/hooks/useCircleWallet";
import { roleStore, type Role } from "@/lib/circle-client";
import { cn } from "@/lib/utils";

const STEPS: { key: Step[]; label: string }[] = [
  { key: ["email", "otp"], label: "Sign in" },
  { key: ["wallet"], label: "Create wallet" },
  { key: ["ready"], label: "Ready" },
];

const ROLES: { id: Role; title: string; blurb: string }[] = [
  { id: "brand", title: "I'm a brand", blurb: "Create a campaign and fund it with USDC." },
  { id: "creator", title: "I'm a creator", blurb: "Join campaigns and get paid per verified view." },
];

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

const primaryBtn =
  "w-full rounded-xl bg-primary px-4 py-3 text-sm font-medium text-white soft-shadow transition hover:brightness-105 disabled:opacity-50 disabled:hover:brightness-100";

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-4" aria-hidden>
      <path fill="#4285F4" d="M23 12.3c0-.8-.1-1.5-.2-2.3H12v4.4h6.2a5.3 5.3 0 0 1-2.3 3.5v2.9h3.7c2.2-2 3.4-5 3.4-8.5Z" />
      <path fill="#34A853" d="M12 24c3.1 0 5.7-1 7.6-2.8l-3.7-2.9c-1 .7-2.3 1.1-3.9 1.1-3 0-5.5-2-6.4-4.7H1.8v3A12 12 0 0 0 12 24Z" />
      <path fill="#FBBC05" d="M5.6 14.7a7.2 7.2 0 0 1 0-4.6v-3H1.8a12 12 0 0 0 0 10.6l3.8-3Z" />
      <path fill="#EA4335" d="M12 4.8c1.7 0 3.2.6 4.4 1.7l3.3-3.3A12 12 0 0 0 1.8 7.1l3.8 3C6.5 6.8 9 4.8 12 4.8Z" />
    </svg>
  );
}

export default function Onboarding() {
  const w = useCircleWallet();
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role | null>(null);
  const [copied, setCopied] = useState(false);

  // Restore the saved role after hydration (localStorage is browser-only).
  useEffect(() => {
    const saved = roleStore.load();
    if (saved) queueMicrotask(() => setRole(saved));
  }, []);

  const pickRole = (r: Role) => {
    roleStore.save(r);
    setRole(r);
  };

  const activeIdx = STEPS.findIndex((s) => s.key.includes(w.step));

  return (
    <div className="mx-auto w-full max-w-md px-4">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-ink">Get started</h1>
        <p className="mt-3 text-muted-foreground">Sign in and get a wallet only you control. No seed phrase.</p>
      </div>

      <ol className="mt-8 flex gap-2 text-xs font-medium">
        {STEPS.map((s, i) => (
          <li key={s.label} className={cn("flex-1 rounded-full px-3 py-1.5 text-center transition", i <= activeIdx ? "bg-ink text-white" : "bg-white text-muted-foreground soft-shadow")}>
            {s.label}
          </li>
        ))}
      </ol>

      <div className="soft-shadow mt-6 rounded-3xl bg-white p-6">
        {w.step === "loading" && <p className="text-sm text-muted-foreground">Loading…</p>}

        {w.step === "email" && (
          <form
            className="space-y-5"
            onSubmit={(e) => {
              e.preventDefault();
              if (role) w.sendOtp(email.trim());
            }}
          >
            <fieldset className="space-y-2.5">
              <legend className="mb-2 text-sm font-semibold text-ink">What brings you here?</legend>
              {ROLES.map((r) => (
                <label key={r.id} className={cn("block cursor-pointer rounded-2xl border p-4 text-sm transition", role === r.id ? "border-primary bg-peri/50" : "border-border hover:border-primary/40")}>
                  <input type="radio" name="role" className="sr-only" checked={role === r.id} onChange={() => pickRole(r.id)} />
                  <span className="font-semibold text-ink">{r.title}</span>
                  <span className="block text-muted-foreground">{r.blurb}</span>
                </label>
              ))}
            </fieldset>

            <button type="button" disabled={w.busy || !role} onClick={w.signInWithGoogle} className="soft-shadow flex w-full items-center justify-center gap-2.5 rounded-xl border border-border bg-white px-4 py-3 text-sm font-medium text-ink transition hover:-translate-y-px disabled:opacity-50">
              <GoogleIcon /> Continue with Google
            </button>

            <div className="flex items-center gap-3 text-xs text-muted-foreground">
              <span className="h-px flex-1 bg-border" /> or use email <span className="h-px flex-1 bg-border" />
            </div>

            <label className="block text-sm font-medium text-ink">
              Email
              <input
                type="email"
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                className="mt-1.5 w-full rounded-xl border border-border bg-white px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
            </label>
            <button disabled={w.busy || !role || !email} className={primaryBtn}>
              {w.busy ? "Sending code…" : "Continue with email"}
            </button>
          </form>
        )}

        {w.step === "otp" && (
          <div className="space-y-4 text-sm">
            <p className="text-ink">We sent a code to <b>{email}</b>. Enter it in the secure window.</p>
            <button onClick={w.verifyOtp} disabled={w.busy} className={primaryBtn}>{w.busy ? "Waiting…" : "Enter code"}</button>
            <button onClick={() => w.setStep("email")} className="w-full text-muted-foreground underline">Use a different email / resend</button>
          </div>
        )}

        {w.step === "wallet" && (
          <div className="space-y-2 text-sm">
            <p className="font-semibold text-ink">Set up your wallet</p>
            <p className="text-muted-foreground">Choose a PIN and security questions in the secure Circle window. We never see them, and nobody can recover the wallet without them.</p>
            {w.busy && <p className="text-muted-foreground">Creating wallet…</p>}
          </div>
        )}

        {w.step === "ready" && w.wallet && (
          <div className="space-y-5 text-sm">
            <p className="flex items-center gap-2 text-base font-semibold text-ink">
              <span className="grid size-6 place-items-center rounded-full bg-ok text-white"><Check className="size-3.5" /></span>
              Your wallet is ready{role ? `, ${role}` : ""}
            </p>
            <dl className="space-y-3 rounded-2xl bg-peri/40 p-4">
              <Row label="Network" value={w.wallet.blockchain} />
              <Row
                label="Address"
                value={
                  <span className="flex items-center gap-2 font-mono">
                    {short(w.wallet.address)}
                    <button
                      aria-label="Copy address"
                      className="text-primary"
                      onClick={() => {
                        navigator.clipboard?.writeText(w.wallet!.address);
                        setCopied(true);
                        setTimeout(() => setCopied(false), 1500);
                      }}
                    >
                      {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
                    </button>
                  </span>
                }
              />
              <Row
                label="USDC balance"
                value={
                  <span className="flex items-center gap-2">
                    {w.usdc}
                    <button aria-label="Refresh balance" className="text-primary" onClick={w.refreshBalance}><RefreshCw className="size-3.5" /></button>
                  </span>
                }
              />
            </dl>
            {role === "brand" && Number(w.usdc) === 0 && (
              <p className="text-muted-foreground">
                Need test USDC? Use the{" "}
                <a className="text-primary underline" href="https://faucet.circle.com" target="_blank" rel="noreferrer">Circle faucet</a>{" "}
                (select Arc Testnet) and paste your address.
              </p>
            )}
            <Link href={role === "creator" ? "/creator" : "/brand"} className={cn(primaryBtn, "block text-center")}>Go to dashboard</Link>
            <button onClick={w.signOut} className="w-full text-muted-foreground underline">Sign out</button>
          </div>
        )}

        {w.error && (
          <p role="alert" className="mt-4 rounded-xl bg-peach/60 p-3 text-sm text-rust">{w.error}</p>
        )}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium text-ink">{value}</dd>
    </div>
  );
}
