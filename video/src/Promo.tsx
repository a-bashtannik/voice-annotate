import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from "remotion";
import { DEMO_SECONDS, Demo } from "./Demo";
import { HOOK_SECONDS, Hook } from "./Hook";
import { OUTPUT_SECONDS, Output } from "./Output";
import { OUTRO_SECONDS, Outro } from "./Outro";
import { theme } from "./theme";
import { sec } from "./timeline";

// Demo → Output is one continuous move (the screen slides aside), so Demo doesn't fade.
const scenes = [
  { C: Hook, length: sec(HOOK_SECONDS), fade: true },
  { C: Demo, length: sec(DEMO_SECONDS), fade: false },
  { C: Output, length: sec(OUTPUT_SECONDS), fade: true },
  { C: Outro, length: sec(OUTRO_SECONDS), fade: false },
];
const starts = scenes.map((_, i) => scenes.slice(0, i).reduce((a, s) => a + s.length, 0));
export const PROMO_FRAMES = starts[starts.length - 1] + scenes[scenes.length - 1].length;

/** Fades a scene out over its last frames; the next scene fades itself in. */
const FadeOut: React.FC<{ length: number; fade: boolean; children: React.ReactNode }> = ({ length, fade, children }) => {
  const frame = useCurrentFrame();
  const o = !fade ? 1 : interpolate(frame, [length - 8, length], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{ background: theme.paper }}>
    {scenes.map(({ C, length, fade }, i) => (
      <Sequence key={i} from={starts[i]} durationInFrames={length}>
        <FadeOut length={length} fade={fade}>
          <C />
        </FadeOut>
      </Sequence>
    ))}
  </AbsoluteFill>
);
