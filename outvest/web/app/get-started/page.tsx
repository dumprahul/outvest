import { Navbar } from "@/components/landing/Navbar";
import Onboarding from "@/components/Onboarding";

export default function GetStarted() {
  return (
    <div className="relative min-h-screen">
      <div className="dot-grid pointer-events-none absolute inset-x-0 top-0 h-[480px] opacity-60" aria-hidden />
      <Navbar />
      <main className="relative z-10 py-12">
        <Onboarding />
      </main>
    </div>
  );
}
