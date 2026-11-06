"use client";

import { createContext, useContext } from "react";
import { useCircleWallet } from "@/hooks/useCircleWallet";

type WalletCtx = ReturnType<typeof useCircleWallet>;
const Ctx = createContext<WalletCtx | null>(null);

/** One Circle wallet session for the whole app, so dashboards can sign transactions. */
export function WalletProvider({ children }: { children: React.ReactNode }) {
  const wallet = useCircleWallet();
  return <Ctx.Provider value={wallet}>{children}</Ctx.Provider>;
}

export function useWallet(): WalletCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error("useWallet must be used inside <WalletProvider>");
  return v;
}
