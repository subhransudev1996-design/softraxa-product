import * as LucideIcons from "lucide-react";

export type IconName = keyof typeof LucideIcons;

/** A Lucide icon by name, for icon lists kept as data. */
export default function LucideIcon({ name, className }: { name: IconName; className?: string }) {
  const C = LucideIcons[name] as LucideIcons.LucideIcon;
  return <C className={className} aria-hidden="true" />;
}
