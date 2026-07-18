import { ArrowRight } from "lucide-react";
import Reveal from "./reveal";
import MagneticButton from "./magnetic-button";
import AuroraBg from "./aurora-bg";

export default function CtaBand({
  title = "Have a business that deserves better software?",
  lead = "Tell us what you're running and we'll show you what Softraxa can build for it.",
  cta = "Start a project",
  href = "/contact",
}: {
  title?: string;
  lead?: string;
  cta?: string;
  href?: string;
}) {
  return (
    <section className="mx-auto max-w-7xl px-6 py-20">
      <Reveal>
        <div className="glass relative overflow-hidden rounded-3xl px-8 py-14 text-center sm:px-16">
          <AuroraBg intensity="soft" />
          <div className="relative">
            <h2 className="mx-auto max-w-2xl font-display text-3xl font-bold tracking-tight sm:text-4xl">
              {title}
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-dim">{lead}</p>
            <div className="mt-8 flex justify-center">
              <MagneticButton href={href}>
                {cta} <ArrowRight className="h-4 w-4" />
              </MagneticButton>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
