import { AppShell } from "@/components/app/AppShell";
import { CreatorDashboard } from "@/components/app/CreatorDashboard";

export default function CreatorPage() {
  return (
    <AppShell role="creator">
      <div className="pt-6">
        <h1 className="text-4xl font-bold text-ink">Your earnings</h1>
        <p className="mt-2 text-muted-foreground">Pay follows verified views, then a fixed unlock schedule. It lands in your wallet automatically.</p>
      </div>
      <CreatorDashboard />
    </AppShell>
  );
}
