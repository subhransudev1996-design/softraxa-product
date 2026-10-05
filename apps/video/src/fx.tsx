import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, easeIO, manrope } from "./theme";

/** Slowly drifting glow + grid behind everything (lives outside the scenes). */
export const Bg: React.FC = () => {
  const f = useCurrentFrame();
  const a = f / 80;
  return (
    <AbsoluteFill style={{ background: "linear-gradient(180deg, #120F2B 0%, #0B0D1E 100%)" }}>
      <div
        style={{
          position: "absolute",
          width: 1200,
          height: 1200,
          left: 330 + Math.sin(a) * 90,
          top: -430 + Math.cos(a * 0.8) * 70,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(124,58,237,.6), rgba(124,58,237,0) 65%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1000,
          height: 1000,
          left: -420 + Math.cos(a * 0.7) * 80,
          top: 1180 + Math.sin(a * 0.9) * 60,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(167,139,250,.32), rgba(167,139,250,0) 62%)",
        }}
      />
      <AbsoluteFill
        style={{
          opacity: 0.07,
          backgroundImage:
            "linear-gradient(#fff 1px, transparent 1px), linear-gradient(90deg, #fff 1px, transparent 1px)",
          backgroundSize: "60px 60px",
          backgroundPosition: `0px ${(f * 0.4) % 60}px`,
          maskImage: "radial-gradient(800px 900px at 50% 40%, #000, transparent)",
          WebkitMaskImage: "radial-gradient(800px 900px at 50% 40%, #000, transparent)",
        }}
      />
    </AbsoluteFill>
  );
};

export const BrandBar: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 0,
      right: 0,
      bottom: 70,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 18,
      fontFamily: manrope,
    }}
  >
    <Img src={staticFile("logo.png")} style={{ width: 64, height: 64, borderRadius: 16 }} />
    <span style={{ color: "#fff", fontWeight: 800, fontSize: 44, letterSpacing: -0.5 }}>Dukania</span>
    <span style={{ color: C.soft, fontWeight: 600, fontSize: 26, marginLeft: 6, opacity: 0.8 }}>
      by SOFTRAXA
    </span>
  </div>
);

export type Word = string | { w: string; hl?: boolean };

/** Chip + two-line headline (word by word) + sub line. */
export const Caption: React.FC<{
  chip: string;
  title: Word[][];
  sub: string;
  delay?: number;
  top?: number;
}> = ({ chip, title, sub, delay = 0.1, top = 150 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sp = (d: number) =>
    spring({ frame: f - Math.round((delay + d) * fps), fps, config: { damping: 200 }, durationInFrames: 22 });
  const chipP = sp(0);
  let n = 0;
  return (
    <div style={{ position: "absolute", left: 70, right: 70, top, fontFamily: manrope }}>
      <div
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 12,
          padding: "12px 26px",
          borderRadius: 999,
          background: "rgba(124,58,237,.25)",
          border: "2px solid rgba(167,139,250,.55)",
          color: "#E9E3FF",
          fontWeight: 800,
          fontSize: 26,
          letterSpacing: 3,
          opacity: chipP,
          transform: `translateY(${(1 - chipP) * -24}px)`,
        }}
      >
        <i style={{ width: 12, height: 12, borderRadius: "50%", background: C.violet2, display: "block" }} />
        {chip}
      </div>
      <div style={{ marginTop: 30, fontWeight: 800, fontSize: 84, lineHeight: 1.04, letterSpacing: -2 }}>
        {title.map((line, li) => (
          <div key={li}>
            {line.map((wd, wi) => {
              const w = typeof wd === "string" ? { w: wd } : wd;
              const p = sp(0.12 + n++ * 0.07);
              return (
                <span
                  key={wi}
                  style={{
                    display: "inline-block",
                    marginRight: 20,
                    color: w.hl ? C.violet2 : "#fff",
                    opacity: p,
                    transform: `translateY(${(1 - p) * 44}px)`,
                  }}
                >
                  {w.w}
                </span>
              );
            })}
          </div>
        ))}
      </div>
      <div
        style={{
          marginTop: 24,
          color: C.soft,
          fontWeight: 600,
          fontSize: 38,
          lineHeight: 1.3,
          opacity: sp(0.12 + n * 0.07 + 0.1),
          transform: `translateY(${(1 - sp(0.12 + n * 0.07 + 0.1)) * 20}px)`,
        }}
      >
        {sub}
      </div>
    </div>
  );
};

const TONES = {
  violet: { bg: C.violet, fg: "#fff" },
  green: { bg: "#22C55E", fg: "#052e13" },
  white: { bg: "#fff", fg: C.ink },
  dark: { bg: "#17223B", fg: "#fff" },
};

/** Floating callout label: pops in at `at` seconds, then bobs a little. */
export const Pill: React.FC<{
  text: string;
  at: number;
  x: number;
  y: number;
  tone?: keyof typeof TONES;
  size?: number;
  until?: number;
}> = ({ text, at, x, y, tone = "violet", size = 36, until }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - Math.round(at * fps), fps, config: { damping: 11, stiffness: 150 } });
  const out = until === undefined ? 1 : interpolate(f, [until * fps, (until + 0.25) * fps], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const t = TONES[tone];
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y + Math.sin(f / 14) * 4,
        transform: `translate(-50%, -50%) scale(${Math.max(0, p) * (0.9 + 0.1 * out)})`,
        opacity: Math.min(1, p * 2) * out,
        padding: "18px 34px",
        borderRadius: 999,
        background: t.bg,
        color: t.fg,
        fontFamily: manrope,
        fontWeight: 800,
        fontSize: size,
        letterSpacing: -0.5,
        whiteSpace: "nowrap",
        boxShadow: "0 18px 40px rgba(0,0,0,.35), 0 0 0 4px rgba(255,255,255,.18)",
      }}
    >
      {text}
    </div>
  );
};

/** A glowing highlight box, in the screen's own coordinates (moves with the camera). */
export const Ring: React.FC<{
  x: number;
  y: number;
  w: number;
  h: number;
  at: number;
  until?: number;
  radius?: number;
}> = ({ x, y, w, h, at, until, radius = 16 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - Math.round(at * fps), fps, config: { damping: 14, stiffness: 120 } });
  const out = until === undefined ? 1 : interpolate(f, [until * fps, (until + 0.3) * fps], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const pulse = 0.5 + 0.5 * Math.sin(f / 7);
  const pad = 14;
  return (
    <div
      style={{
        position: "absolute",
        left: x - pad,
        top: y - pad,
        width: w + pad * 2,
        height: h + pad * 2,
        borderRadius: radius + 6,
        border: "6px solid #7C3AED",
        boxShadow: `0 0 0 5px rgba(255,255,255,.9), 0 0 ${30 + pulse * 30}px rgba(124,58,237,.85)`,
        opacity: Math.max(0, Math.min(1, p * 1.5)) * out,
        transform: `scale(${1 + (1 - Math.min(1, p)) * 0.18})`,
        pointerEvents: "none",
      }}
    />
  );
};

/** A tap: a dot that pulses outwards, in the screen's own coordinates. */
export const Tap: React.FC<{ x: number; y: number; at: number }> = ({ x, y, at }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = (f - Math.round(at * fps)) / (0.55 * fps);
  if (t < 0 || t > 1) return null;
  const r = 14 + t * 70;
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: x - r,
          top: y - r,
          width: r * 2,
          height: r * 2,
          borderRadius: "50%",
          border: "5px solid rgba(124,58,237,.9)",
          opacity: 1 - t,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: x - 11,
          top: y - 11,
          width: 22,
          height: 22,
          borderRadius: "50%",
          background: "#7C3AED",
          boxShadow: "0 0 0 4px rgba(255,255,255,.9)",
          opacity: 1 - t * 0.6,
        }}
      />
    </>
  );
};

/** A number that counts from `from` to `to`. */
export const Count: React.FC<{
  from: number;
  to: number;
  at: number;
  dur?: number;
  prefix?: string;
  style?: React.CSSProperties;
}> = ({ from, to, at, dur = 1, prefix = "₹", style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const v = interpolate(f, [at * fps, (at + dur) * fps], [from, to], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: easeIO,
  });
  return <span style={style}>{prefix + Math.round(v).toLocaleString("en-IN")}</span>;
};
