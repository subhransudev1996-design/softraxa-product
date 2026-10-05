import React from "react";
import { AbsoluteFill, Composition } from "remotion";
import { Bg } from "./fx";
import { DesktopReel, desktopFrames } from "./DesktopReel";
import { Billing, Bills, Brand, Checkout, Cta, D, Dashboard, Hook, Khata, Tray, Trust } from "./scenes";
import { FPS, H, W } from "./theme";
import { Youtube, ytFrames } from "./yt/Yt";
import { YFPS, YH, YW } from "./yt/data";
import { Thumb } from "./yt/anim";
import { YBg } from "./yt/parts";

/** One scene on the background — to preview and tune it on its own. */
const On = (C: React.FC) => () => (
  <AbsoluteFill>
    <Bg />
    <C />
  </AbsoluteFill>
);

const scenes: [string, React.FC, number][] = [
  ["S-hook", Hook, D.hook],
  ["S-brand", Brand, D.brand],
  ["S-billing", Billing, D.billing],
  ["S-tray", Tray, D.tray],
  ["S-checkout", Checkout, D.checkout],
  ["S-bills", Bills, D.bills],
  ["S-khata", Khata, D.khata],
  ["S-dashboard", Dashboard, D.dashboard],
  ["S-trust", Trust, D.trust],
  ["S-cta", () => <Cta line1="Try" note="WhatsApp us for a free demo" />, D.cta],
];

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="DesktopReel" component={DesktopReel} durationInFrames={desktopFrames} fps={FPS} width={W} height={H} />
    <Composition id="Youtube" component={Youtube} durationInFrames={ytFrames} fps={YFPS} width={YW} height={YH} />
    <Composition id="Thumb" component={() => (<AbsoluteFill><YBg /><Thumb /></AbsoluteFill>)} durationInFrames={1} fps={30} width={1280} height={720} />
    {scenes.map(([id, C, frames]) => (
      <Composition key={id} id={id} component={On(C)} durationInFrames={frames} fps={FPS} width={W} height={H} />
    ))}
  </>
);
