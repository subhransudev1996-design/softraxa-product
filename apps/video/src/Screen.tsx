import React from "react";
import {
  AbsoluteFill,
  Img,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, W, easeIO } from "./theme";

/** The camera: which part of the recorded screen is visible `t` seconds into a cut. */
export type View = { t: number; x: number; y: number; w: number };

export type Cut = {
  src: string; // file under public/
  still?: boolean;
  from?: number; // source seconds (video)
  to?: number;
  rate?: number; // playback speed
  dur?: number; // seconds (stills)
  views: View[];
  /** Highlights and taps, in the screen's own pixels; `at` is seconds into the cut. */
  layer?: React.ReactNode;
  /** The visible size of the recording (a few bottom pixels are the taskbar peeking in). */
  sw?: number;
  sh?: number;
  /** The recording's real size. */
  nw?: number;
  nh?: number;
};

const CROSS = 7; // frames: a quick dissolve between two cuts of the same panel

export const cutFrames = (c: Cut, fps: number) =>
  Math.round((c.still ? (c.dur ?? 3) : ((c.to ?? 0) - (c.from ?? 0)) / (c.rate ?? 1)) * fps);

export const cutsFrames = (cuts: Cut[], fps: number) => cuts.reduce((s, c) => s + cutFrames(c, fps), 0);

const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

const camera = (views: View[], t: number): View => {
  if (t <= views[0].t) return views[0];
  for (let i = 0; i < views.length - 1; i++) {
    const a = views[i];
    const b = views[i + 1];
    if (t < b.t) {
      const p = easeIO((t - a.t) / (b.t - a.t));
      return { t, x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p), w: lerp(a.w, b.w, p) };
    }
  }
  return views[views.length - 1];
};

const CutLayer: React.FC<{ cut: Cut; pw: number; fade: boolean }> = ({ cut, pw, fade }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const v = camera(cut.views, f / fps);
  const s = pw / v.w;
  const sw = cut.sw ?? 1920;
  const sh = cut.sh ?? 1018;
  const nw = cut.nw ?? 1920;
  const nh = cut.nh ?? 1028;
  return (
    <AbsoluteFill style={{ opacity: fade ? interpolate(f, [0, CROSS], [0, 1], { extrapolateRight: "clamp" }) : 1 }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: sw,
          height: sh,
          overflow: "hidden",
          transformOrigin: "0 0",
          transform: `translate(${-v.x * s}px, ${-v.y * s}px) scale(${s})`,
        }}
      >
        {cut.still ? (
          <Img src={staticFile(cut.src)} style={{ position: "absolute", left: 0, top: 0, width: nw, height: nh }} />
        ) : (
          <OffthreadVideo
            src={staticFile(cut.src)}
            trimBefore={Math.round((cut.from ?? 0) * fps)}
            playbackRate={cut.rate ?? 1}
            muted
            style={{ position: "absolute", left: 0, top: 0, width: nw, height: nh }}
          />
        )}
        {cut.layer}
      </div>
    </AbsoluteFill>
  );
};

/** A rounded panel showing the recorded app, cut together and followed by a smooth camera. */
export const Screen: React.FC<{
  cuts: Cut[];
  pw?: number;
  ph?: number;
  top?: number;
  left?: number;
  bg?: string;
  children?: React.ReactNode; // callouts, in panel coordinates
}> = ({ cuts, pw = 1000, ph = 860, top = 590, left, bg = C.canvas, children }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: f - 6, fps, config: { damping: 200 }, durationInFrames: 26 });
  let start = 0;
  return (
    <div
      style={{
        position: "absolute",
        left: left ?? (W - pw) / 2,
        top: top + (1 - enter) * 170,
        width: pw,
        height: ph,
        opacity: Math.min(1, enter * 2),
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 38,
          overflow: "hidden",
          background: bg,
          boxShadow: "0 44px 100px rgba(0,0,0,.6), 0 0 0 2px rgba(255,255,255,.1)",
        }}
      >
      {cuts.map((c, i) => {
        const dur = cutFrames(c, fps);
        const from = start;
        start += dur;
        const last = i === cuts.length - 1;
        return (
          <Sequence key={i} from={from} durationInFrames={dur + (last ? 0 : CROSS)} layout="none">
            <CutLayer cut={c} pw={pw} fade={i > 0} />
          </Sequence>
        );
      })}
      </div>
      {/* callouts live outside the clipped panel, so they can sit on its edge */}
      {children}
    </div>
  );
};
