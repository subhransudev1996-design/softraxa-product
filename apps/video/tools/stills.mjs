// node tools/stills.mjs S-billing:30,90 S-tray:60  -> out/stills/<id>_<frame>.png
// Bundles once, then renders the requested frames of the requested compositions.
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import fs from "node:fs";

const root = path.resolve(import.meta.dirname, "..");
const outDir = path.join(root, "out", "stills");
fs.mkdirSync(outDir, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.join(root, "src", "index.ts"), publicDir: path.join(root, "public") });
for (const arg of process.argv.slice(2)) {
  const [id, frames] = arg.split(":");
  const composition = await selectComposition({ serveUrl, id });
  for (const f of frames.split(",").map(Number)) {
    const output = path.join(outDir, `${id}_${f}.png`);
    await renderStill({ composition, serveUrl, frame: f, output, imageFormat: "png" });
    console.log("ok", id, f);
  }
}
