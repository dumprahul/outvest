"use client";

import { Check, Copy } from "lucide-react";
import { useState } from "react";
import { useWallet } from "@/components/WalletProvider";

export function WalletBadge() {
  const { wallet, usdc } = useWallet();
  const [copied, setCopied] = useState(false);
  if (!wallet) return null;
  return (
    <button
      onClick={() => { void navigator.clipboard?.writeText(wallet.address); setCopied(true); setTimeout(() => setCopied(false), 1500); }}
      className="soft-shadow hidden items-center gap-2 rounded-xl bg-white px-3 py-2 font-mono text-xs text-ink sm:flex"
      title="Copy wallet address"
    >
      <span className="size-2 rounded-full bg-ok" /> {wallet.address.slice(0, 6)}…{wallet.address.slice(-4)} · ${Number(usdc).toFixed(2)}
      {copied ? <Check className="size-3.5 text-ok" /> : <Copy className="size-3.5 text-muted-foreground" />}
    </button>
  );
}
