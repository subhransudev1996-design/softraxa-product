import Image from "next/image";

/** The Dukania icon, the same one as the app and website. */
export function BrandMark({ size = 32 }: { size?: number }) {
  return (
    <Image
      src="/images/dukania/icon.png"
      alt="Dukania"
      width={size}
      height={size}
      className="shrink-0 rounded-lg"
      style={{ width: size, height: size }}
      priority
    />
  );
}
