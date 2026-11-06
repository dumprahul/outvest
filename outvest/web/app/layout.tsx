import type { Metadata } from "next";
import "@fontsource-variable/inter";
import "./globals.css";
import { WalletProvider } from "@/components/WalletProvider";

export const metadata: Metadata = {
  title: "OutVest",
  description: "Escrowed USDC payouts for YouTube creators",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className="h-full antialiased"
    >
      <body className="min-h-full flex flex-col bg-background text-foreground"><WalletProvider>{children}</WalletProvider></body>
    </html>
  );
}
