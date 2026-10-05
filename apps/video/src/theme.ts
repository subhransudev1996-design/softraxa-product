import { loadFont as loadManrope } from "@remotion/google-fonts/Manrope";
import { loadFont as loadCaveat } from "@remotion/google-fonts/Caveat";
import { Easing } from "remotion";

export const W = 1080;
export const H = 1920;
export const FPS = 30;

export const manrope = loadManrope("normal", {
  weights: ["500", "600", "700", "800"],
  subsets: ["latin", "latin-ext"],
}).fontFamily;
export const caveat = loadCaveat("normal", {
  weights: ["600"],
  subsets: ["latin", "latin-ext"],
}).fontFamily;

export const C = {
  violet: "#7C3AED",
  violet2: "#A78BFA",
  ink: "#17223B",
  soft: "#C9C2F5",
  green: "#22C55E",
  wa: "#25D366",
  red: "#F87171",
  canvas: "#F4F6FB",
};

/** Fast start, long soft landing — for things arriving on screen. */
export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
/** Smooth both ways — for camera moves. */
export const easeIO = Easing.bezier(0.45, 0, 0.2, 1);
