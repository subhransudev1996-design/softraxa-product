import Image from "next/image";

/** The Dukania mark: the app icon and the name beside it. */
export default function BrandLogo({ size = 36 }: { size?: number }) {
  return (
    <span className="flex items-center gap-2.5">
      <Image
        src="/images/dukania/icon.png"
        alt=""
        width={size}
        height={size}
        className="rounded-[10px]"
        style={{ width: size, height: size }}
        priority
      />
      <span className="font-display text-2xl font-bold tracking-tight text-brand">Dukania</span>
    </span>
  );
}
