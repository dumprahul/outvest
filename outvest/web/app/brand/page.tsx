import { AppShell } from "@/components/app/AppShell";
import { BrandDashboard } from "@/components/app/BrandDashboard";

export default function BrandPage() {
  return (
    <AppShell role="brand">
      <div className="pt-6">
        <h1 className="text-4xl font-bold text-ink">Campaigns</h1>
        <p className="mt-2 text-muted-foreground">Funds are escrowed in each vault. You can&apos;t withdraw mid-campaign, and neither can we.</p>
      </div>
      <BrandDashboard />
    </AppShell>
  );
}
