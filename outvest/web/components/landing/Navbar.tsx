import Link from "next/link";
import { Logo } from "@/components/Logo";

const links = [
  { href: "#how-it-works", label: "How it works" },
  { href: "#creators", label: "For creators" },
  { href: "#brands", label: "For brands" },
  { href: "#rules", label: "Rules" },
];

export function Navbar() {
  return (
    <header className="relative z-20 mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-5">
      <Logo />
      <nav className="hidden items-center gap-9 text-[15px] font-medium text-ink/80 md:flex">
        {links.map((l) => (
          <a key={l.href} href={l.href} className="transition-colors hover:text-ink">
            {l.label}
          </a>
        ))}
      </nav>
      <div className="flex items-center gap-2">
        <Link
          href="/get-started"
          className="soft-shadow rounded-xl bg-white px-4 py-2 text-[15px] font-medium text-ink transition hover:-translate-y-px"
        >
          Log in
        </Link>
        <Link
          href="/get-started"
          className="soft-shadow rounded-xl bg-primary px-4 py-2 text-[15px] font-medium text-white transition hover:-translate-y-px hover:brightness-105"
        >
          Sign up
        </Link>
      </div>
    </header>
  );
}
