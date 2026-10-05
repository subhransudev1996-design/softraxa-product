import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { Cut, Screen, View } from "../Screen";
import { Cta, Everywhere, Hook, Meet, Offline, PdfShare, PhoneSplit, Questions, Trial, Wizard } from "./anim";
import { SCENES, Sc, YFPS } from "./data";
import { Cap, Edge, Sub, YBg } from "./parts";

const PW = 1510;
const PH = 800;
const PTOP = 40;
const PLEFT = 205;

/** A recorded stretch of the app, played at whatever speed fills `dur` seconds. */
const clip = (src: string, from: number, to: number, dur: number, views: View[]): Cut => ({
  src: `raw/${src}`,
  from,
  to,
  rate: (to - from) / dur,
  views,
});
const still = (src: string, dur: number, views: View[]): Cut => ({ src, still: true, dur, views });
const full = (t = 0): View => ({ t, x: 0, y: 0, w: 1920 });
const zoom = (t: number, x: number, y: number, w: number): View => ({ t, x, y, w });

const cutsFor: Record<number, Cut[]> = {
  6: [clip("d.mp4", 3, 33, 10, [full(0), zoom(1.5, 295, 40, 1625), zoom(5, 295, 320, 1300), zoom(8, 295, 330, 1625)])],
  7: [clip("f.mp4", 9, 17, 8, [full(0), full(8)])],
  8: [clip("billing.mp4", 8.5, 20.5, 12, [zoom(0, 295, 40, 1625), zoom(12, 295, 40, 1625)])],
  9: [clip("g.mp4", 3.5, 15.5, 12, [zoom(0, 295, 40, 1625), zoom(3.5, 440, 290, 1040), zoom(9, 295, 40, 1625)])],
  10: [
    clip("billing.mp4", 18, 24, 9.5, [zoom(0, 295, 40, 1625), zoom(2, 560, 270, 900)]),
    clip("billing.mp4", 27, 32, 6.5, [zoom(0, 560, 270, 900), zoom(3, 295, 40, 1625)]),
  ],
  11: [
    clip("g.mp4", 16.5, 22.5, 7.5, [zoom(0, 295, 40, 1625), zoom(1.5, 600, 60, 1100)]),
    clip("billing.mp4", 40, 44.5, 7.5, [zoom(0, 440, 20, 1100), zoom(3, 480, 330, 950)]),
  ],
  13: [still("yt/bill_desktop.png", 13, [full(0), zoom(1.8, 295, 100, 1625), zoom(11, 295, 100, 1625)])],
  14: [
    still("yt/customers_desktop.png", 7, [full(0), zoom(1.5, 295, 100, 1625)]),
    still("yt/sunita_desktop.png", 8, [full(0), zoom(1.5, 295, 40, 1625)]),
  ],
  15: [clip("khata.mp4", 10, 23, 15, [zoom(0, 295, 40, 1625), zoom(1.5, 560, 220, 1000), zoom(10, 295, 40, 1625)])],
  16: [
    clip("f.mp4", 1.5, 4.4, 4.5, [zoom(0, 295, 40, 1625)]),
    still("yt/lowstock_desktop.png", 7.5, [zoom(0, 295, 40, 1625), zoom(2, 295, 120, 1300)]),
  ],
  17: [clip("e.mp4", 3, 47, 18, [zoom(0, 295, 40, 1625), zoom(6, 295, 40, 1625), zoom(14, 295, 160, 1500)])],
  18: [still("raw/dashboard.png", 12, [full(0), zoom(2, 300, 130, 1620), zoom(8, 300, 130, 1620)])],
  19: [still("yt/sales_desktop.png", 13, [full(0), zoom(2, 295, 40, 1625), zoom(8, 295, 40, 1625)])],
};

const Clip: React.FC<{ sc: Sc }> = ({ sc }) => (
  <>
    <Screen cuts={cutsFor[sc.n]} pw={PW} ph={PH} top={PTOP} left={PLEFT} />
    <Cap text={sc.cap} bottom={135} />
  </>
);

const art: Record<number, React.FC> = {
  1: Hook,
  2: Questions,
  3: Meet,
  4: Everywhere,
  5: Wizard,
  12: PdfShare,
  20: PhoneSplit,
  21: Offline,
  22: Trial,
  23: Cta,
};

const Body: React.FC<{ sc: Sc }> = ({ sc }) => {
  if (cutsFor[sc.n]) return <Clip sc={sc} />;
  const A = art[sc.n];
  const noCap = sc.n === 23 || sc.n === 22;
  return (
    <>
      <A />
      {!noCap && <Cap text={sc.cap} bottom={135} />}
    </>
  );
};

export const ytFrames = SCENES.reduce((s, x) => s + Math.round(x.sec * YFPS), 0);

export const Youtube: React.FC = () => {
  let at = 0;
  return (
    <AbsoluteFill>
      <YBg />
      {SCENES.map((sc) => {
        const frames = Math.round(sc.sec * YFPS);
        const from = at;
        at += frames;
        return (
          <Sequence key={sc.n} from={from} durationInFrames={frames} name={`${sc.n}`}>
            <Edge frames={frames}>
              <Body sc={sc} />
              <Sub text={sc.sub} />
            </Edge>
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
