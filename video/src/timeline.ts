import data from "./demo-data.json";

export const FPS = 30;
export const CANVAS = { w: data.canvas[0], h: data.canvas[1] };

// The demo narration is the real capture, trimmed: the intro and one aside are cut, so
// source seconds map onto demo seconds with two kept stretches.
const KEEP = [
  { from: 2.4, to: 7.4, at: 0 },
  { from: 10.0, to: 18.7, at: 5.0 },
];
/** Demo-scene seconds at which the narration starts (after the hotkey and freeze). */
export const NARRATION_START = 1.3;
export const NARRATION_LENGTH = 13.7;

const toDemo = (src: number): number | null => {
  const k = KEEP.find((r) => src >= r.from && src <= r.to);
  return k ? NARRATION_START + k.at + (src - k.from) : null;
};

export type Word = { text: string; start: number; end: number };
export const words: Word[] = data.words
  .map((w) => ({ text: w.t, start: toDemo(w.s), end: toDemo(w.e) }))
  .filter((w): w is Word => w.start !== null && w.end !== null);

/** Sentences of the narration, for captions. */
export const phrases: Word[][] = words.reduce<Word[][]>((acc, w) => {
  const last = acc[acc.length - 1];
  if (!last || /[.?!]$/.test(last[last.length - 1].text)) acc.push([w]);
  else last.push(w);
  return acc;
}, []);

export type Pt = { x: number; y: number };
export type Mark = {
  id: number;
  tool: "ellipse" | "rectangle" | "arrow";
  color: string;
  start: number;
  end: number;
  points: Pt[];
  label: string;
};

const colors: Record<string, string> = { red: "#ff3b30", blue: "#0a84ff" };
const labels = ["circled", "circled", "box", "arrow"];
// Drawing takes a touch longer than in the capture so it reads on video.
export const marks: Mark[] = data.marks.map((m, i) => {
  const start = toDemo(m.start)!;
  return {
    id: i + 1,
    tool: m.tool as Mark["tool"],
    color: colors[m.color],
    start,
    end: start + Math.max(0.75, m.end - m.start),
    points: m.points.map(([x, y]) => ({ x, y })),
    label: labels[i],
  };
});

export const bounds = (m: Mark) => {
  const xs = m.points.map((p) => p.x), ys = m.points.map((p) => p.y);
  return { minX: Math.min(...xs), maxX: Math.max(...xs), minY: Math.min(...ys), maxY: Math.max(...ys) };
};

export const sec = (s: number) => Math.round(s * FPS);
