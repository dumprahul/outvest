import { OAuthReturn } from "@/components/landing/OAuthReturn";
import { Navbar } from "@/components/landing/Navbar";
import { Hero } from "@/components/landing/Hero";
import { Features, AllPurpose } from "@/components/landing/Features";
import { CtaFooter } from "@/components/landing/Footer";

export default function Home() {
  return (
    <main className="flex-1">
      <OAuthReturn />
      <Navbar />
      <Hero />
      <Features />
      <AllPurpose />
      <CtaFooter />
    </main>
  );
}
