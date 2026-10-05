// node tools/package.mjs -> youtube/dukania-english.srt
import fs from "node:fs";
import path from "node:path";
const src = fs.readFileSync(path.resolve(import.meta.dirname, "../src/yt/data.ts"), "utf8");
const scenes = [...src.matchAll(/n: (\d+), sec: (\d+), cap: "([^"]*)", sub: "([^"]*)"/g)].map((m) => ({
  n: +m[1],
  sec: +m[2],
  cap: m[3],
  sub: m[4],
}));
const ts = (s) => {
  const ms = Math.round(s * 1000);
  const p = (n, l = 2) => String(n).padStart(l, "0");
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
};
let at = 0;
let i = 1;
let srt = "";
for (const s of scenes) {
  srt += `${i++}\n${ts(at + 0.4)} --> ${ts(at + s.sec - 0.3)}\n${s.sub}\n\n`;
  at += s.sec;
}
fs.writeFileSync(path.resolve(import.meta.dirname, "../youtube/dukania-english.srt"), srt);
console.log("scenes", scenes.length, "total", at);
