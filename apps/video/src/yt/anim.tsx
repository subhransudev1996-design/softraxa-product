import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, caveat, manrope } from "../theme";
import { Laptop, Logo, Note, Phone, Pill, WaIcon, useIn } from "./parts";

const H1: React.FC<{ children: React.ReactNode; size?: number; color?: string; style?: React.CSSProperties }> = ({
  children,
  size = 96,
  color = "#fff",
  style,
}) => (
  <div style={{ fontFamily: manrope, fontWeight: 800, fontSize: size, letterSpacing: -2, color, lineHeight: 1.08, ...style }}>
    {children}
  </div>
);

/** 1: the old way: notes, sums, a late night. */
export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = f / fps;
  const clock = t < 3 ? "7:40 PM" : t < 5.5 ? "10:15 PM" : "11:48 PM";
  const total = Math.round(interpolate(t, [0, 6], [900, 1437], { extrapolateRight: "clamp" }));
  return (
    <AbsoluteFill>
      <Note text="Ramesh — 2 kg sugar 92" x={190} y={190} rot={-4} delay={0.2} />
      <Note text="Sunita — udhaar 240 → 465 ??" x={620} y={360} rot={3} delay={1.0} />
      <Note text="Gupta — 1 tray eggs …" x={150} y={520} rot={-2} delay={1.8} />
      <Note text={`Total = ${total.toLocaleString("en-IN")} ✗`} x={760} y={640} rot={5} delay={2.6} size={52} />
      <div
        style={{
          position: "absolute",
          right: 170,
          top: 150,
          fontFamily: manrope,
          fontWeight: 800,
          fontSize: 120,
          color: t > 5.5 ? C.red : "#fff",
          letterSpacing: -3,
        }}
      >
        {clock}
      </div>
    </AbsoluteFill>
  );
};

/** 2: the three questions every shop owner asks. */
export const Questions: React.FC = () => {
  const qs = ["Kisne kitna udhaar liya?", "Kaunsa maal kam hai?", "Aaj kitna kamaya?"];
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 28, flexDirection: "column", paddingBottom: 90 }}>
      {qs.map((q, i) => {
        const p = useIn(0.5 + i * 2.6, 16);
        return (
          <div
            key={q}
            style={{
              opacity: p,
              transform: `translateY(${(1 - p) * 50}px) scale(${0.94 + p * 0.06})`,
              display: "flex",
              alignItems: "center",
              gap: 36,
              background: "rgba(255,255,255,.07)",
              border: "2px solid rgba(167,139,250,.35)",
              borderRadius: 36,
              padding: "30px 64px",
            }}
          >
            <span style={{ fontFamily: manrope, fontWeight: 800, fontSize: 110, color: C.violet2 }}>?</span>
            <span style={{ fontFamily: manrope, fontWeight: 800, fontSize: 82, color: "#fff", letterSpacing: -1.5 }}>{q}</span>
          </div>
        );
      })}
      <H1 size={64} color={C.red} style={{ opacity: useIn(8.5), marginTop: 20 }}>
        Jawab nahi milta.
      </H1>
    </AbsoluteFill>
  );
};

/** 3: meet Dukania. */
export const Meet: React.FC = () => {
  const p = useIn(0.2, 14);
  const l = useIn(1.2);
  const ph = useIn(1.8);
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 130, top: 190, opacity: p, transform: `translateY(${(1 - p) * 40}px)` }}>
        <Logo size={150} />
        <H1 size={150} style={{ marginTop: 28 }}>Dukania</H1>
        <H1 size={46} color={C.violet2} style={{ marginTop: 14, letterSpacing: 0 }}>
          Billing · Stock · Udhaar
        </H1>
      </div>
      <Laptop src="yt/dashboard.png" w={980} style={{ left: 760, top: 170, opacity: l, transform: `translateX(${(1 - l) * 120}px)` }} />
      <Phone src="yt/ph_now.png" h={640} style={{ left: 1500, top: 330, opacity: ph, transform: `translateY(${(1 - ph) * 140}px)` }} />
    </AbsoluteFill>
  );
};

/** 4: on every device, for every kind of shop. */
export const Everywhere: React.FC = () => {
  const l = useIn(0.2);
  const ph = useIn(0.7);
  const shops = ["Kirana", "Mobile shop", "Hardware", "Kapde"];
  return (
    <AbsoluteFill>
      <Laptop src="yt/dashboard.png" w={1000} style={{ left: 170, top: 150, opacity: l, transform: `translateY(${(1 - l) * 80}px)` }} />
      <Phone src="yt/ph_cart.png" h={660} style={{ left: 1290, top: 140, opacity: ph, transform: `translateY(${(1 - ph) * 120}px)` }} />
      {shops.map((s, i) => (
        <Pill key={s} text={s} delay={1.6 + i * 0.35} x={190 + i * 300 - (i === 1 ? 20 : 0)} y={700} />
      ))}
    </AbsoluteFill>
  );
};

const Field: React.FC<{ label: string; value: string; delay: number }> = ({ label, value, delay }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const n = Math.max(0, Math.min(value.length, Math.floor(((f / fps - delay) * 14))));
  return (
    <div style={{ marginTop: 26 }}>
      <div style={{ fontFamily: manrope, fontWeight: 600, fontSize: 24, color: "#6b7280" }}>{label}</div>
      <div
        style={{
          marginTop: 8,
          fontFamily: manrope,
          fontWeight: 700,
          fontSize: 38,
          color: C.ink,
          border: "2px solid #e5e7eb",
          borderRadius: 16,
          padding: "16px 24px",
          minHeight: 48,
        }}
      >
        {value.slice(0, n)}
      </div>
    </div>
  );
};

/** 5: the setup wizard, a sketch (replace with a real recording when available). */
export const Wizard: React.FC = () => {
  const p = useIn(0.2);
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = f / fps;
  const type = t > 5 ? "Kirana" : "";
  return (
    <AbsoluteFill style={{ alignItems: "center", paddingTop: 90 }}>
      <div
        style={{
          width: 980,
          background: "#fff",
          borderRadius: 36,
          padding: "46px 60px 56px",
          boxShadow: "0 40px 100px rgba(0,0,0,.5)",
          opacity: p,
          transform: `translateY(${(1 - p) * 80}px)`,
        }}
      >
        <div style={{ fontFamily: manrope, fontWeight: 800, fontSize: 52, color: C.ink }}>Set up your shop</div>
        <Field label="Shop name" value="Sharma General Store" delay={1.2} />
        <div style={{ marginTop: 26 }}>
          <div style={{ fontFamily: manrope, fontWeight: 600, fontSize: 24, color: "#6b7280" }}>Shop type</div>
          <div style={{ display: "flex", gap: 14, marginTop: 8 }}>
            {["Grocery", "Mobile", "Hardware", "Clothes"].map((x) => {
              const on = x === "Grocery" && t > 4.6;
              return (
                <span
                  key={x}
                  style={{
                    fontFamily: manrope,
                    fontWeight: 700,
                    fontSize: 32,
                    padding: "14px 30px",
                    borderRadius: 99,
                    background: on ? C.violet : "#f3f4f6",
                    color: on ? "#fff" : C.ink,
                  }}
                >
                  {x}
                </span>
              );
            })}
          </div>
        </div>
        <Field label="Phone" value="82609 66559" delay={6.2} />
        <div
          style={{
            marginTop: 40,
            textAlign: "center",
            fontFamily: manrope,
            fontWeight: 800,
            fontSize: 38,
            color: "#fff",
            padding: "22px 0",
            borderRadius: 18,
            background: t > 9.5 ? C.green : C.violet,
          }}
        >
          {t > 9.5 ? "✓ Ready" : "Continue"}
        </div>
      </div>
      <Pill text="2 minute" delay={2} x={1400} y={140} />
      <div style={{ display: "none" }}>{type}</div>
    </AbsoluteFill>
  );
};

/** 12: a bill PDF, then the phone's share sheet. */
export const PdfShare: React.FC = () => {
  const a = useIn(0.2);
  const b = useIn(1.2);
  const s = useIn(3.2, 16);
  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: 150,
          top: 170,
          width: 940,
          background: "#fff",
          borderRadius: 14,
          overflow: "hidden",
          boxShadow: "0 40px 90px rgba(0,0,0,.55)",
          opacity: a,
          transform: `rotate(${-2 + a * 0}deg) translateY(${(1 - a) * 80}px)`,
        }}
      >
        <Img src={staticFile("yt/pdf.png")} style={{ width: "100%", display: "block" }} />
      </div>
      <Phone src="yt/ph_bill.png" h={800} style={{ left: 1260, top: 90, opacity: b, transform: `translateY(${(1 - b) * 120}px)` }}>
      </Phone>
      <div
        style={{
          position: "absolute",
          left: 1230,
          top: 520 + (1 - s) * 80,
          width: 400,
          opacity: s,
          background: "#fff",
          borderRadius: 26,
          padding: "26px 28px",
          boxShadow: "0 30px 70px rgba(0,0,0,.55)",
        }}
      >
        <div style={{ fontFamily: manrope, fontWeight: 800, fontSize: 28, color: C.ink, marginBottom: 18 }}>Share file</div>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <WaIcon size={84} />
          <span style={{ fontFamily: manrope, fontWeight: 700, fontSize: 30, color: C.ink }}>WhatsApp</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** 20: the same shop on phone and computer. */
export const PhoneSplit: React.FC = () => {
  const l = useIn(0.2);
  const p = useIn(0.8);
  return (
    <AbsoluteFill>
      <Laptop src="yt/dashboard.png" w={1000} style={{ left: 120, top: 220, opacity: l, transform: `translateX(${(1 - l) * -100}px)` }} />
      <div
        style={{
          position: "absolute",
          left: 1260,
          top: 40,
          opacity: p,
          transform: `translateY(${(1 - p) * 120}px)`,
        }}
      >
        <div
          style={{
            width: 460,
            borderRadius: 54,
            background: "#0b0b14",
            padding: 10,
            boxShadow: "0 40px 90px rgba(0,0,0,.6), 0 0 0 2px rgba(255,255,255,.16)",
          }}
        >
          <div style={{ borderRadius: 44, overflow: "hidden", height: 880 }}>
            <OffthreadVideo
              src={staticFile("raw/phone.mp4")}
              trimBefore={Math.round(2 * 30)}
              muted
              style={{ width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }}
            />
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** 21: offline billing, step by step on the real phone. */
export const Offline: React.FC = () => {
  const steps: [string, string][] = [
    ["Airplane mode ON", "yt/ph_off_clean.png"],
    ["Bill saved offline", "yt/ph_off_after.png"],
    ["Back online", "yt/ph_online_again.png"],
    ["Synced as INV/26-27/0052", "yt/ph_now.png"],
  ];
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const active = Math.min(3, Math.floor(f / fps / 2.4));
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 170, top: 190, display: "flex", flexDirection: "column", gap: 34 }}>
        {steps.map(([s], i) => {
          const p = useIn(0.4 + i * 0.4, 16);
          const on = i === active;
          return (
            <div key={s} style={{ display: "flex", alignItems: "center", gap: 28, opacity: p * (on ? 1 : 0.5), transform: `translateX(${(1 - p) * -60}px)` }}>
              <span
                style={{
                  width: 76,
                  height: 76,
                  borderRadius: "50%",
                  background: on ? C.violet : "rgba(255,255,255,.12)",
                  color: "#fff",
                  fontFamily: manrope,
                  fontWeight: 800,
                  fontSize: 40,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                {i + 1}
              </span>
              <span style={{ fontFamily: manrope, fontWeight: 800, fontSize: 56, color: "#fff", letterSpacing: -1 }}>{s}</span>
            </div>
          );
        })}
      </div>
      <Phone src={steps[active][1]} h={800} style={{ left: 1260, top: 100 }} />
    </AbsoluteFill>
  );
};

/** 22: three reasons to trust it, and the free trial. */
export const Trial: React.FC = () => {
  const items = ["Works offline", "Phone + Computer", "Data safe in the cloud"];
  const b = useIn(3, 12);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 56, paddingBottom: 80 }}>
      <div style={{ display: "flex", gap: 28 }}>
        {items.map((s, i) => {
          const p = useIn(0.4 + i * 0.5, 16);
          return (
            <div
              key={s}
              style={{
                opacity: p,
                transform: `translateY(${(1 - p) * 50}px)`,
                background: "rgba(255,255,255,.08)",
                border: "2px solid rgba(167,139,250,.4)",
                borderRadius: 32,
                padding: "34px 40px",
                fontFamily: manrope,
                fontWeight: 800,
                fontSize: 42,
                color: "#fff",
              }}
            >
              ✓ {s}
            </div>
          );
        })}
      </div>
      <div
        style={{
          opacity: b,
          transform: `scale(${0.7 + b * 0.3})`,
          fontFamily: manrope,
          fontWeight: 800,
          fontSize: 120,
          letterSpacing: -3,
          color: "#fff",
          padding: "26px 80px",
          borderRadius: 40,
          background: "linear-gradient(135deg, #7C3AED, #A78BFA)",
          boxShadow: "0 30px 80px rgba(124,58,237,.6)",
        }}
      >
        7-DAY FREE TRIAL
      </div>
    </AbsoluteFill>
  );
};

/** 23: call to action. */
export const Cta: React.FC = () => {
  const a = useIn(0.2, 14);
  const b = useIn(1.4);
  const c = useIn(2.2);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 30, paddingBottom: 60 }}>
      <Logo size={150} style={{ opacity: a, transform: `scale(${0.7 + a * 0.3})` }} />
      <H1 size={130} style={{ opacity: a }}>
        Try <span style={{ color: C.violet2 }}>Dukania</span>
      </H1>
      <H1 size={92} style={{ opacity: b, transform: `translateY(${(1 - b) * 30}px)` }}>
        softraxa.in
      </H1>
      <div style={{ display: "flex", alignItems: "center", gap: 24, opacity: c, transform: `translateY(${(1 - c) * 30}px)` }}>
        <WaIcon size={76} />
        <span style={{ fontFamily: manrope, fontWeight: 800, fontSize: 60, color: "#fff" }}>WhatsApp +91 82609 66559</span>
      </div>
      <div style={{ fontFamily: caveat, fontSize: 64, color: C.violet2, opacity: c }}>7 din free trial</div>
    </AbsoluteFill>
  );
};

/** The YouTube thumbnail, designed at 1920x1080 and scaled to 1280x720 by the composition. */
export const Thumb: React.FC = () => (
  <AbsoluteFill style={{ transform: "scale(0.6667)", transformOrigin: "0 0", width: 1920, height: 1080 }}>
    <div style={{ position: "absolute", left: 90, top: 120 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 24 }}>
        <Logo size={110} />
        <span style={{ fontFamily: manrope, fontWeight: 800, fontSize: 84, color: "#fff", letterSpacing: -2 }}>Dukania</span>
      </div>
      <H1 size={128} style={{ marginTop: 54, lineHeight: 1.02 }}>
        Dukaan ka
        <br />
        <span style={{ color: C.violet2 }}>poora hisaab</span>
      </H1>
      <H1 size={52} color={C.soft} style={{ marginTop: 30, letterSpacing: 0 }}>
        Billing · Stock · Udhaar
      </H1>
      <div
        style={{
          marginTop: 44,
          display: "inline-block",
          fontFamily: manrope,
          fontWeight: 800,
          fontSize: 60,
          color: "#fff",
          padding: "18px 48px",
          borderRadius: 99,
          background: "linear-gradient(135deg, #7C3AED, #A78BFA)",
          boxShadow: "0 18px 50px rgba(124,58,237,.6)",
        }}
      >
        7 din FREE trial
      </div>
    </div>
    <Laptop src="yt/dashboard.png" w={780} style={{ left: 1010, top: 300, transform: "rotate(-3deg)" }} />
    <Phone src="yt/ph_now.png" h={740} style={{ left: 1500, top: 200, transform: "rotate(3deg)" }} />
  </AbsoluteFill>
);
