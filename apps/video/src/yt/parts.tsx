import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, caveat, manrope } from "../theme";
import { YH, YW } from "./data";

/** Spring 0 → 1, `delay` seconds after the scene starts. */
export const useIn = (delay = 0, damping = 200) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - Math.round(delay * fps), fps, config: { damping }, durationInFrames: 28 });
};

/** Dark violet background with two slow glows. */
export const YBg: React.FC = () => {
  const f = useCurrentFrame();
  const a = f / 90;
  return (
    <AbsoluteFill style={{ background: "linear-gradient(180deg, #120F2B 0%, #0B0D1E 100%)" }}>
      <div
        style={{
          position: "absolute",
          width: 1300,
          height: 1300,
          left: 1100 + Math.sin(a) * 90,
          top: -640 + Math.cos(a * 0.8) * 60,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(124,58,237,.55), rgba(124,58,237,0) 65%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1100,
          height: 1100,
          left: -520 + Math.cos(a * 0.7) * 70,
          top: 600 + Math.sin(a * 0.9) * 60,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(167,139,250,.28), rgba(167,139,250,0) 62%)",
        }}
      />
      <AbsoluteFill
        style={{
          opacity: 0.06,
          backgroundImage:
            "linear-gradient(#fff 1px, transparent 1px), linear-gradient(90deg, #fff 1px, transparent 1px)",
          backgroundSize: "64px 64px",
          maskImage: "radial-gradient(1100px 700px at 50% 45%, #000, transparent)",
          WebkitMaskImage: "radial-gradient(1100px 700px at 50% 45%, #000, transparent)",
        }}
      />
    </AbsoluteFill>
  );
};

/** Fades a scene in and out at its edges so cuts feel soft. */
export const Edge: React.FC<{ frames: number; children: React.ReactNode }> = ({ frames, children }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 9, frames - 9, frames], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

/** The on-screen headline of a scene (storyboard's "On screen" line). */
export const Cap: React.FC<{ text: string; bottom?: number; left?: number | "center" }> = ({
  text,
  bottom = 150,
  left = "center",
}) => {
  const p = useIn(0.5);
  return (
    <div
      style={{
        position: "absolute",
        left: left === "center" ? 0 : left,
        right: left === "center" ? 0 : undefined,
        bottom,
        display: "flex",
        justifyContent: left === "center" ? "center" : "flex-start",
        opacity: p,
        transform: `translateY(${(1 - p) * 26}px)`,
      }}
    >
      <span
        style={{
          fontFamily: manrope,
          fontWeight: 800,
          fontSize: 46,
          letterSpacing: -0.5,
          color: "#fff",
          background: "rgba(14,12,34,.9)",
          padding: "16px 36px",
          borderRadius: 99,
          boxShadow: "0 0 0 3px rgba(167,139,250,.6), 0 18px 50px rgba(0,0,0,.45)",
        }}
      >
        {text}
      </span>
    </div>
  );
};

/** English subtitle strip under the picture. */
export const Sub: React.FC<{ text: string }> = ({ text }) => {
  const p = useIn(0.3);
  return (
    <div
      style={{
        position: "absolute",
        left: 160,
        right: 160,
        bottom: 34,
        textAlign: "center",
        fontFamily: manrope,
        fontWeight: 600,
        fontSize: 34,
        lineHeight: 1.3,
        color: "#fff",
        textShadow: "0 2px 14px rgba(0,0,0,.85)",
        opacity: p,
      }}
    >
      {text}
    </div>
  );
};

export const Logo: React.FC<{ size: number; style?: React.CSSProperties }> = ({ size, style }) => (
  <Img src={staticFile("yt/logo.png")} style={{ width: size, height: size, borderRadius: size * 0.24, ...style }} />
);

/** A desktop window showing a screenshot. */
export const Laptop: React.FC<{ src: string; w: number; style?: React.CSSProperties }> = ({ src, w, style }) => (
  <div
    style={{
      position: "absolute",
      width: w,
      borderRadius: 18,
      overflow: "hidden",
      background: "#fff",
      boxShadow: "0 40px 90px rgba(0,0,0,.55), 0 0 0 2px rgba(255,255,255,.12)",
      ...style,
    }}
  >
    <Img src={staticFile(src)} style={{ width: "100%", display: "block" }} />
  </div>
);

/** A phone showing a screenshot (1260x2800 portrait) or any child. */
export const Phone: React.FC<{ src?: string; h: number; style?: React.CSSProperties; children?: React.ReactNode }> = ({
  src,
  h,
  style,
  children,
}) => {
  const w = (h * 1260) / 2800;
  return (
    <div
      style={{
        position: "absolute",
        width: w + 20,
        height: h + 20,
        borderRadius: 54,
        background: "#0b0b14",
        padding: 10,
        boxShadow: "0 40px 90px rgba(0,0,0,.6), 0 0 0 2px rgba(255,255,255,.16)",
        ...style,
      }}
    >
      <div style={{ width: w, height: h, borderRadius: 44, overflow: "hidden", position: "relative", background: "#f4f6fb" }}>
        {src ? <Img src={staticFile(src)} style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : children}
      </div>
    </div>
  );
};

/** A cream paper note in handwriting. */
export const Note: React.FC<{ text: string; x: number; y: number; rot: number; delay: number; size?: number }> = ({
  text,
  x,
  y,
  rot,
  delay,
  size = 40,
}) => {
  const p = useIn(delay, 14);
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y + (1 - p) * -120,
        transform: `rotate(${rot}deg) scale(${0.85 + p * 0.15})`,
        opacity: Math.min(1, p * 2),
        background: "#FBF3DC",
        color: "#3a3220",
        fontFamily: caveat,
        fontWeight: 600,
        fontSize: size,
        padding: "22px 34px",
        borderRadius: 6,
        boxShadow: "0 22px 50px rgba(0,0,0,.45)",
        whiteSpace: "nowrap",
      }}
    >
      {text}
    </div>
  );
};

export const Pill: React.FC<{ text: string; delay: number; x: number; y: number }> = ({ text, delay, x, y }) => {
  const p = useIn(delay, 16);
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        opacity: p,
        transform: `scale(${0.7 + p * 0.3})`,
        fontFamily: manrope,
        fontWeight: 800,
        fontSize: 40,
        color: "#fff",
        padding: "16px 38px",
        borderRadius: 99,
        background: "linear-gradient(135deg, #7C3AED, #A78BFA)",
        boxShadow: "0 18px 40px rgba(124,58,237,.5)",
      }}
    >
      {text}
    </div>
  );
};

export const WaIcon: React.FC<{ size: number }> = ({ size }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: "50%",
      background: C.wa,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      boxShadow: "0 10px 30px rgba(37,211,102,.5)",
    }}
  >
    <svg width={size * 0.58} height={size * 0.58} viewBox="0 0 24 24" fill="#fff">
      <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3a.5.5 0 0 0 0-.5c-.1-.1-.6-1.4-.8-1.9s-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.8 11.9 11.9 0 0 0 4.6 4c1.7.7 2.4.8 3.2.7a2.7 2.7 0 0 0 1.8-1.3 2.2 2.2 0 0 0 .2-1.3c-.1-.1-.3-.2-.6-.3z" />
    </svg>
  </div>
);

export { YW, YH };
