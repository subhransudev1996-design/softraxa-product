"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { Play, X } from "lucide-react";

/**
 * The 2-minute film as a photo card; the video loads only when someone
 * presses play (it is the heaviest thing on the site).
 */
export default function FilmCard({ id = "film" }: { id?: string }) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <>
      <button
        id={id}
        type="button"
        onClick={() => setOpen(true)}
        className="group relative block w-full scroll-mt-24 overflow-hidden rounded-3xl text-left shadow-card"
        aria-label="Play the 2-minute film: a day at the counter"
      >
        <Image
          src="/images/site/film-poster.jpg"
          alt="A shop owner scanning a packet at his counter"
          width={1672}
          height={941}
          sizes="(max-width: 1024px) 100vw, 50vw"
          className="aspect-[16/10] h-auto w-full object-cover transition-transform duration-500 group-hover:scale-[1.03]"
        />
        <span className="absolute inset-0 bg-gradient-to-t from-black/45 via-black/5 to-transparent" />
        <span className="absolute left-1/2 top-1/2 flex h-20 w-20 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white/25 ring-2 ring-white/80 backdrop-blur transition-transform group-hover:scale-110">
          <Play className="ml-1 h-9 w-9 fill-white text-white" aria-hidden="true" />
        </span>
        <span className="hand absolute bottom-10 left-6 -rotate-6 text-left text-3xl leading-tight text-white drop-shadow sm:text-4xl">
          A day
          <br />
          at the counter
        </span>
        <span className="absolute bottom-4 left-6 text-sm font-semibold text-white/90">2:00</span>
      </button>

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Dukania film"
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/80 p-4"
          onClick={() => setOpen(false)}
        >
          <div className="relative w-full max-w-5xl" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="absolute -top-12 right-0 inline-flex h-10 w-10 items-center justify-center rounded-full bg-white/15 text-white hover:bg-white/25"
              aria-label="Close the film"
            >
              <X className="h-5 w-5" />
            </button>
            <video
              src="/videos/dukania-film.mp4"
              poster="/videos/dukania-film-poster.jpg"
              controls
              autoPlay
              playsInline
              className="aspect-video w-full rounded-2xl bg-black"
            />
          </div>
        </div>
      )}
    </>
  );
}
