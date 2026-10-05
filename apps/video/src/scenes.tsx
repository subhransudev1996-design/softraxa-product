import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { BrandBar, Caption, Count, Pill, Ring, Tap } from "./fx";
import { Cut, Screen, cutsFrames } from "./Screen";
import { C, caveat, easeOut, manrope } from "./theme";

const FPS = 30;
const BILLING = "raw/billing.mp4";
const KHATA = "raw/khata.mp4";

/* ------------------------------------------------------------------ *
 *  Scenes made of animation only
 * ------------------------------------------------------------------ */

type Part = { t: string; hl?: "red" | "blue" | "strike" };
const REGISTER: Part[][] = [
  [{ t: "Ramesh — 2 kg sugar  92" }],
  [{ t: "Sunita — udhaar " }, { t: "240", hl: "strike" }, { t: " 465 ??" }],
  [{ t: "Gupta — 1 tray eggs …" }],
  [{ t: "Total = 1,4" }, { t: "3", hl: "strike" }, { t: "7  ✗" }],
  [{ t: "Stock? don't know…" }],
];

const Reveal: React.FC<{ parts: Part[]; n: number }> = ({ parts, n }) => {
  let left = n;
  return (
    <>
      {parts.map((p, i) => {
        const shown = p.t.slice(0, Math.max(0, left));
        left -= p.t.length;
        return (
          <span
            key={i}
            style={{
              color: p.hl === "strike" ? "#B91C1C" : undefined,
              textDecoration: p.hl === "strike" ? "line-through" : undefined,
            }}
          >
            {shown}
          </span>
        );
      })}
    </>
  );
};

export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: f, fps, config: { damping: 16, stiffness: 90 } });
  const wobble = Math.sin(f / 9) * 0.6;
  const wordP = (i: number) =>
    spring({ frame: f - Math.round((1.15 + i * 0.12) * fps), fps, config: { damping: 14, stiffness: 140 } });
  const words = ["Still keeping", "accounts in a"];
  return (
    <AbsoluteFill style={{ fontFamily: manrope }}>
      <div
        style={{
          position: "absolute",
          left: 190,
          top: 200,
          width: 700,
          height: 800,
          background: "#FFFDF5",
          borderRadius: 18,
          overflow: "hidden",
          boxShadow: "0 50px 100px rgba(0,0,0,.55)",
          transform: `translateY(${(1 - enter) * 420}px) rotate(${-14 + 8 * enter + wobble}deg)`,
        }}
      >
        <div style={{ position: "absolute", left: 90, top: 0, bottom: 0, width: 3, background: "#F2A0A0" }} />
        <div
          style={{
            position: "absolute",
            inset: 0,
            top: 40,
            background: "repeating-linear-gradient(#FFFDF5 0 58px, #BFD4F2 58px 60px)",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 120,
            right: 30,
            top: 70,
            fontFamily: caveat,
            fontSize: 48,
            color: "#1E3A8A",
            lineHeight: "60px",
          }}
        >
          {REGISTER.map((parts, i) => {
            const total = parts.reduce((s, p) => s + p.t.length, 0);
            const n = interpolate(f, [(0.45 + i * 0.32) * fps, (0.45 + i * 0.32 + 0.5) * fps], [0, total], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            return (
              <div key={i} style={{ whiteSpace: "nowrap" }}>
                <Reveal parts={parts} n={Math.floor(n)} />
              </div>
            );
          })}
        </div>
      </div>
      <div style={{ position: "absolute", left: 60, right: 60, top: 1180, textAlign: "center", fontWeight: 800, fontSize: 92, lineHeight: 1.05, letterSpacing: -2.5, color: "#fff" }}>
        {words.map((w, i) => (
          <div key={w} style={{ opacity: wordP(i), transform: `translateY(${(1 - wordP(i)) * 50}px)` }}>
            {w}
          </div>
        ))}
        <div style={{ color: "#FCA5A5", opacity: wordP(2), transform: `translateY(${(1 - wordP(2)) * 50}px) scale(${0.9 + 0.1 * wordP(2)})` }}>
          register?
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const Brand: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: f - 2, fps, config: { damping: 11, stiffness: 120 } });
  const word = "Dukania".split("");
  const fadeUp = (d: number) =>
    spring({ frame: f - Math.round(d * fps), fps, config: { damping: 200 }, durationInFrames: 24 });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: manrope, textAlign: "center" }}>
      <div style={{ position: "relative", width: 260, height: 260 }}>
        {[0, 1, 2].map((i) => {
          const t = ((f + i * 20) % 60) / 60;
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                inset: -t * 140,
                borderRadius: 70 + t * 100,
                border: `4px solid rgba(167,139,250,${0.55 * (1 - t)})`,
              }}
            />
          );
        })}
        <Img
          src={staticFile("logo.png")}
          style={{ position: "relative", width: 260, height: 260, borderRadius: 64, transform: `scale(${pop})`, boxShadow: "0 30px 90px rgba(124,58,237,.65)" }}
        />
      </div>
      <div style={{ marginTop: 50, fontWeight: 800, fontSize: 160, letterSpacing: -5, color: "#fff", display: "flex" }}>
        {word.map((ch, i) => {
          const p = spring({ frame: f - Math.round((0.35 + i * 0.05) * fps), fps, config: { damping: 14, stiffness: 160 } });
          return (
            <span key={i} style={{ display: "inline-block", opacity: Math.min(1, p * 2), transform: `translateY(${(1 - p) * 70}px)` }}>
              {ch}
            </span>
          );
        })}
      </div>
      <div style={{ marginTop: 14, color: C.soft, fontWeight: 700, fontSize: 48, opacity: fadeUp(0.95), transform: `translateY(${(1 - fadeUp(0.95)) * 24}px)` }}>
        Billing &amp; stock software for your shop
      </div>
      <div style={{ marginTop: 30, display: "flex", gap: 14 }}>
        {["Grocery", "Mobile", "Hardware", "Garments"].map((c, i) => (
          <span
            key={c}
            style={{
              padding: "12px 26px",
              borderRadius: 999,
              background: "rgba(255,255,255,.08)",
              border: "2px solid rgba(255,255,255,.16)",
              color: "#fff",
              fontSize: 30,
              fontWeight: 700,
              opacity: fadeUp(1.15 + i * 0.1),
              transform: `translateY(${(1 - fadeUp(1.15 + i * 0.1)) * 20}px)`,
            }}
          >
            {c}
          </span>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const icon = (d: React.ReactNode) => (
  <svg viewBox="0 0 24 24" width="60" height="60" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
    {d}
  </svg>
);
const ICONS = {
  offline: icon(
    <>
      <path d="M2 2l20 20" />
      <path d="M8.5 16.4a5 5 0 0 1 7 0" />
      <path d="M5 12.9a10 10 0 0 1 5.2-2.7" />
      <path d="M19 12.9a10 10 0 0 0-2.3-1.7" />
      <path d="M2 8.8a15 15 0 0 1 4.2-2.6" />
      <path d="M10.7 5.1A15 15 0 0 1 22 8.8" />
      <circle cx="12" cy="20" r="1" />
    </>,
  ),
  devices: icon(
    <>
      <rect x="2" y="4" width="14" height="10" rx="1.5" />
      <path d="M6 18h6" />
      <rect x="17" y="8" width="5" height="12" rx="1.2" />
    </>,
  ),
  cloud: icon(
    <>
      <path d="M17.5 19a4.5 4.5 0 0 0 0-9h-1.3A7 7 0 1 0 4 15.3" />
      <path d="M9 15l2 2 4-4" />
    </>,
  ),
};

export const Trust: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = (d: number) => spring({ frame: f - Math.round(d * fps), fps, config: { damping: 15, stiffness: 120 } });
  const rows = [
    { i: ICONS.offline, b: "Works offline", s: "Keep billing when the internet is down" },
    { i: ICONS.devices, b: "Phone + Computer", s: "Android app and Windows software" },
    { i: ICONS.cloud, b: "Data safe in the cloud", s: "Change phones without losing a bill" },
  ];
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: manrope }}>
      <div style={{ color: "#fff", fontWeight: 800, fontSize: 78, letterSpacing: -2, marginBottom: 64, opacity: p(0), transform: `translateY(${(1 - p(0)) * 40}px)` }}>
        Built for Indian shops
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 34, width: 900 }}>
        {rows.map((r, i) => {
          const q = p(0.35 + i * 0.3);
          return (
            <div
              key={r.b}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 34,
                padding: "34px 40px",
                borderRadius: 34,
                background: "rgba(255,255,255,.07)",
                border: "2px solid rgba(255,255,255,.14)",
                opacity: Math.min(1, q * 1.6),
                transform: `translateX(${(1 - q) * 160}px)`,
              }}
            >
              <div style={{ width: 112, height: 112, borderRadius: 30, background: "linear-gradient(135deg,#7C3AED,#A78BFA)", display: "grid", placeItems: "center", flex: "none", transform: `scale(${0.6 + 0.4 * q})` }}>
                {r.i}
              </div>
              <div>
                <div style={{ color: "#fff", fontSize: 52, fontWeight: 800, letterSpacing: -1 }}>{r.b}</div>
                <div style={{ color: C.soft, fontSize: 33, fontWeight: 600, marginTop: 6 }}>{r.s}</div>
              </div>
            </div>
          );
        })}
      </div>
      <BrandBar />
    </AbsoluteFill>
  );
};

const WA = (
  <svg viewBox="0 0 24 24" width="52" height="52" fill="#fff">
    <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.8 11.9 11.9 0 0 0 4.6 4c1.7.7 2.4.8 3.2.7.5-.1 1.5-.6 1.7-1.2s.2-1.1.2-1.2l-.6-.2z" />
  </svg>
);

export const Cta: React.FC<{ line1: string; note: string }> = ({ line1, note }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = (d: number, cfg: { damping?: number; stiffness?: number } = { damping: 14, stiffness: 130 }) => spring({ frame: f - Math.round(d * fps), fps, config: cfg });
  const shine = interpolate(f, [1.6 * fps, 2.4 * fps], [-120, 120], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: easeOut });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: manrope, textAlign: "center" }}>
      <div style={{ padding: "16px 36px", borderRadius: 999, background: "rgba(34,197,94,.16)", border: "2px solid rgba(34,197,94,.6)", color: "#86EFAC", fontWeight: 800, fontSize: 34, letterSpacing: 2, transform: `scale(${p(0)})` }}>
        7-DAY FREE TRIAL
      </div>
      <div style={{ marginTop: 44, color: "#fff", fontWeight: 800, fontSize: 112, lineHeight: 1.02, letterSpacing: -3.5 }}>
        {[line1, "Dukania"].map((w, i) => {
          const q = p(0.25 + i * 0.18, { damping: 200, stiffness: 100 });
          return (
            <div key={w} style={{ opacity: q, transform: `translateY(${(1 - q) * 50}px)`, color: i === 1 ? C.violet2 : "#fff" }}>
              {w}
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 74, position: "relative", overflow: "hidden", padding: "32px 66px", borderRadius: 999, background: "#fff", color: C.ink, fontWeight: 800, fontSize: 70, letterSpacing: -1, transform: `scale(${p(0.85)})` }}>
        softraxa.in
        <div style={{ position: "absolute", top: 0, bottom: 0, width: 90, left: `${50 + shine}%`, background: "linear-gradient(90deg, transparent, rgba(124,58,237,.28), transparent)", transform: "skewX(-20deg)" }} />
      </div>
      <div style={{ marginTop: 46, display: "flex", alignItems: "center", gap: 22, color: "#fff", fontSize: 56, fontWeight: 800, opacity: p(1.15, { damping: 200 }), transform: `translateY(${(1 - p(1.15, { damping: 200 })) * 30}px)` }}>
        <div style={{ width: 88, height: 88, borderRadius: "50%", background: C.wa, display: "grid", placeItems: "center" }}>{WA}</div>
        +91 82609 66559
      </div>
      <div style={{ marginTop: 28, color: C.soft, fontSize: 34, fontWeight: 600, opacity: p(1.5, { damping: 200 }) }}>{note}</div>
      <BrandBar />
    </AbsoluteFill>
  );
};

/* ------------------------------------------------------------------ *
 *  Scenes made of the recorded app
 * ------------------------------------------------------------------ */

// Camera positions, in pixels of the recorded 1920x1018 screen.
const CART = { x: 316, y: 40, w: 1160 }; // the whole bill table
const SEARCH = { x: 330, y: 100, w: 800 }; // search box and results
const SHEET = { x: 560, y: 200, w: 800 }; // quantity pop-up
const CHECKOUT = { x: 500, y: 60, w: 940 }; // the whole checkout pop-up
const PROFIT = { x: 585, y: 300, w: 730 }; // profit line down to the Create bill button

export const billingCuts: Cut[] = [
  {
    src: BILLING,
    from: 5.5,
    to: 15.0,
    rate: 1.4,
    views: [
      { t: 0, ...CART },
      { t: 1.0, ...CART },
      { t: 1.9, ...SEARCH },
      { t: 3.2, ...SEARCH },
      { t: 3.9, ...SHEET },
      { t: 5.5, ...SHEET },
      { t: 6.2, ...CART },
    ],
  },
];
export const Billing: React.FC = () => (
  <AbsoluteFill>
    <Caption chip="FAST BILLING" title={[["Make", "a", "bill"], ["in", { w: "seconds", hl: true }]]} sub="Type a few letters, add. Loose items by the kg too." />
    <Screen cuts={billingCuts}>
      <Pill text="By the kg, gram or litre" at={4.3} x={500} y={900} tone="white" until={6.0} />
    </Screen>
    <BrandBar />
  </AbsoluteFill>
);

export const trayCuts: Cut[] = [
  {
    src: BILLING,
    from: 16.2,
    to: 23.2,
    rate: 1.6,
    views: [
      { t: 0, ...SEARCH },
      { t: 0.5, ...SEARCH },
      { t: 0.9, ...SHEET },
      { t: 3.2, ...SHEET },
      { t: 3.8, ...CART },
    ],
    layer: (
      <>
        <Ring x={965} y={462} w={262} h={44} at={2.0} until={3.2} />
        <Tap x={1096} y={484} at={2.05} />
      </>
    ),
  },
  {
    src: BILLING,
    from: 25.2,
    to: 31.2,
    rate: 1.6,
    views: [
      { t: 0, ...SHEET },
      { t: 2.9, ...SHEET },
      { t: 3.5, ...CART },
    ],
  },
];
export const Tray: React.FC = () => (
  <AbsoluteFill>
    <Caption chip="BOX & LOOSE" title={[["Sell", "by", "the", "tray"], ["or", { w: "by the piece", hl: true }]]} sub="Each at its own price: ₹190 a tray, ₹7 an egg." />
    <Screen cuts={trayCuts}>
      <Pill text="₹190 per tray" at={2.3} x={500} y={900} tone="violet" until={4.0} />
      <Pill text="₹7 per piece" at={5.5} x={500} y={900} tone="white" until={8.0} />
    </Screen>
    <BrandBar />
  </AbsoluteFill>
);

export const checkoutCuts: Cut[] = [
  {
    src: BILLING,
    from: 33.5,
    to: 39.2,
    rate: 3,
    views: [{ t: 0, ...SHEET }],
  },
  {
    src: BILLING,
    from: 40.2,
    to: 44.4,
    rate: 1.0,
    views: [
      { t: 0, ...CHECKOUT },
      { t: 1.0, ...CHECKOUT },
      { t: 1.8, ...PROFIT },
    ],
    layer: <Ring x={615} y={609} w={696} h={50} at={1.9} />,
  },
];
export const Checkout: React.FC = () => (
  <AbsoluteFill>
    <Caption chip="CHECKOUT" title={[["Cash,", "UPI", "or"], [{ w: "credit", hl: true }]]} sub="See your profit on every bill. Your customer doesn’t." />
    <Screen cuts={checkoutCuts}>
      <Pill text="Your profit — hidden from the customer" at={2.6} x={500} y={900} tone="green" size={34} />
    </Screen>
    <BrandBar />
  </AbsoluteFill>
);

export const billsCuts: Cut[] = [
  {
    src: BILLING,
    from: 46.4,
    to: 48.9,
    views: [{ t: 0, x: 740, y: 330, w: 1160 }],
  },
  {
    src: "raw/pdf.png",
    still: true,
    dur: 3.5,
    sw: 990,
    sh: 500,
    nw: 990,
    nh: 500,
    views: [
      { t: 0, x: 0, y: 0, w: 990 },
      { t: 3.5, x: 0, y: 0, w: 990 },
    ],
  },
];
export const Bills: React.FC = () => (
  <AbsoluteFill>
    <Caption chip="BILLS" title={[["Clean", "bills,"], [{ w: "print", hl: true }, "or", "PDF"]]} sub="Your shop’s name and phone on every bill." />
    <Screen cuts={billsCuts} ph={600} top={760} bg="#fff">
      <Pill text="Share PDF · A4 · Thermal printer" at={0.5} x={500} y={640} tone="violet" size={32} until={2.4} />
    </Screen>
    <BrandBar />
  </AbsoluteFill>
);

const LEDGER = { x: 316, y: 120, w: 1200 };
export const khataCuts: Cut[] = [
  { src: KHATA, from: 2.6, to: 4.6, views: [{ t: 0, x: 300, y: 110, w: 1640 }] },
  { src: KHATA, from: 6.6, to: 8.4, views: [{ t: 0, ...LEDGER }] },
  {
    src: KHATA,
    from: 10.8,
    to: 16.0,
    rate: 1.8,
    views: [{ t: 0, x: 560, y: 170, w: 800 }],
  },
  {
    src: KHATA,
    from: 17.3,
    to: 21.3,
    rate: 1.2,
    views: [{ t: 0, ...LEDGER }],
  },
];
export const Khata: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const showAt = (2.0 + 1.8 + 2.9 + 0.5) * fps;
  const p = spring({ frame: f - Math.round(showAt), fps, config: { damping: 11, stiffness: 150 } });
  return (
    <AbsoluteFill>
      <Caption chip="UDHAAR · KHATA" title={[["Every", "customer’s"], [{ w: "credit", hl: true }, "tracked"]]} sub="Take a payment and old bills clear by themselves." />
      <Screen cuts={khataCuts}>
        <div
          style={{
            position: "absolute",
            left: 500,
            top: 900,
            transform: `translate(-50%, -50%) scale(${Math.max(0, p)})`,
            opacity: Math.min(1, p * 2),
            padding: "18px 40px",
            borderRadius: 999,
            background: "#17223B",
            color: "#fff",
            fontFamily: manrope,
            fontWeight: 800,
            fontSize: 40,
            whiteSpace: "nowrap",
            boxShadow: "0 18px 40px rgba(0,0,0,.35), 0 0 0 4px rgba(255,255,255,.18)",
          }}
        >
          Sunita’s due{" "}
          <Count from={265} to={65} at={(2.0 + 1.8 + 2.9 + 0.7)} dur={1.1} style={{ color: "#86EFAC" }} />
        </div>
      </Screen>
      <BrandBar />
    </AbsoluteFill>
  );
};

const DASH_LEFT = { x: 316, y: 110, w: 840 };
const DASH_RIGHT = { x: 1090, y: 110, w: 830 };
const DASH_CHART = { x: 326, y: 290, w: 1040 };
export const dashCuts: Cut[] = [
  {
    src: "raw/dashboard.png",
    still: true,
    dur: 5.5,
    views: [
      { t: 0, ...DASH_LEFT },
      { t: 1.8, ...DASH_LEFT },
      { t: 2.6, ...DASH_RIGHT },
      { t: 3.6, ...DASH_RIGHT },
      { t: 4.4, ...DASH_CHART },
    ],
  },
];
export const Dashboard: React.FC = () => (
  <AbsoluteFill>
    <Caption chip="DASHBOARD" title={[["Sales,", "profit,", "stock"], [{ w: "at a glance", hl: true }]]} sub="Know your day before you close the shop." />
    <Screen cuts={dashCuts}>
      <Pill text="Today’s sale and profit" at={0.6} x={500} y={900} tone="white" until={1.9} />
      <Pill text="Low-stock alerts" at={2.8} x={500} y={900} tone="violet" until={3.8} />
      <Pill text="30-day sales trend" at={4.6} x={500} y={900} tone="white" />
    </Screen>
    <BrandBar />
  </AbsoluteFill>
);

/* durations (frames) */
export const D = {
  hook: Math.round(4.0 * FPS),
  brand: Math.round(3.2 * FPS),
  billing: cutsFrames(billingCuts, FPS),
  tray: cutsFrames(trayCuts, FPS),
  checkout: cutsFrames(checkoutCuts, FPS),
  bills: cutsFrames(billsCuts, FPS),
  khata: cutsFrames(khataCuts, FPS),
  dashboard: cutsFrames(dashCuts, FPS),
  trust: Math.round(4.6 * FPS),
  cta: Math.round(6.6 * FPS),
};
