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
      // Browser extensions (e.g. data-cap-chrome-extension-installed) add attributes to <html> before React
      // hydrates; this silences that one-level mismatch only, not mismatches in the app's own markup.
      suppressHydrationWarning
    >
      <body className="min-h-full flex flex-col bg-background text-foreground"><WalletProvider>{children}</WalletProvider></body>
    </html>
  );
}
