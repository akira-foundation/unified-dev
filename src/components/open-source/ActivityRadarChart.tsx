import type { ActivityBreakdown } from "@/types/openSource";

interface ActivityRadarChartProps {
  breakdown: ActivityBreakdown;
  size?: number;
}

const AXES: Array<{ key: keyof ActivityBreakdown; label: string; angle: number }> = [
  { key: "codeReview", label: "Code review", angle: -90 },
  { key: "issues", label: "Issues", angle: 0 },
  { key: "pullRequests", label: "Pull requests", angle: 90 },
  { key: "commits", label: "Commits", angle: 180 },
];

function polar(angleDeg: number, r: number) {
  const rad = (angleDeg * Math.PI) / 180;
  return { x: Math.cos(rad) * r, y: Math.sin(rad) * r };
}

export function ActivityRadarChart({ breakdown, size = 220 }: ActivityRadarChartProps) {
  const cx = size / 2;
  const cy = size / 2;
  const maxR = size / 2 - 40;

  const points = AXES.map((axis) => {
    const value = breakdown[axis.key];
    const r = (value / 100) * maxR;
    const p = polar(axis.angle, r);
    return { x: cx + p.x, y: cy + p.y };
  });

  const polygon = points.map((p) => `${p.x},${p.y}`).join(" ");

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="text-emerald-500">
      {AXES.map((axis) => {
        const end = polar(axis.angle, maxR);
        return (
          <line
            key={axis.key}
            x1={cx}
            y1={cy}
            x2={cx + end.x}
            y2={cy + end.y}
            stroke="currentColor"
            strokeOpacity={0.4}
            strokeWidth={1}
          />
        );
      })}

      <polygon
        points={polygon}
        fill="currentColor"
        fillOpacity={0.25}
        stroke="currentColor"
        strokeWidth={1.5}
      />

      {points.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r={3} fill="currentColor" />
      ))}

      {AXES.map((axis) => {
        const labelP = polar(axis.angle, maxR + 22);
        const value = breakdown[axis.key];
        return (
          <g key={`l-${axis.key}`} transform={`translate(${cx + labelP.x}, ${cy + labelP.y})`}>
            <text
              textAnchor="middle"
              className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-semibold"
            >
              {Math.round(value)}%
            </text>
            <text
              y={11}
              textAnchor="middle"
              className="fill-zinc-400 dark:fill-zinc-500 text-[9px]"
            >
              {axis.label}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
