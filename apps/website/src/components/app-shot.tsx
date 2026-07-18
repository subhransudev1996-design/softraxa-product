import Image from "next/image";
import type { Shot } from "@/lib/shots";
import { BrowserFrame, PhoneFrame } from "./device-frame";

/**
 * A real Dukania screenshot inside device chrome. Replaces the CSS-drawn
 * mock screens — these are the actual app. `priority` only on above-the-fold
 * hero shots; everything else lazy-loads.
 */
export function DesktopShot({
  shot,
  label = "Dukania",
  priority = false,
  className = "",
}: {
  shot: Shot;
  label?: string;
  priority?: boolean;
  className?: string;
}) {
  return (
    <BrowserFrame label={label} className={className}>
      <Image
        src={shot.src}
        width={shot.width}
        height={shot.height}
        alt={shot.alt}
        priority={priority}
        sizes="(max-width: 1024px) 100vw, 60vw"
        className="h-auto w-full rounded-lg"
      />
    </BrowserFrame>
  );
}

export function MobileShot({
  shot,
  priority = false,
  className = "",
}: {
  shot: Shot;
  priority?: boolean;
  className?: string;
}) {
  return (
    <PhoneFrame className={className}>
      <Image
        src={shot.src}
        width={shot.width}
        height={shot.height}
        alt={shot.alt}
        priority={priority}
        sizes="(max-width: 640px) 60vw, 264px"
        className="h-auto w-full rounded-[1.4rem]"
      />
    </PhoneFrame>
  );
}
