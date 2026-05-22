export interface WordSeg {
  text: string;
  changed: boolean;
}

function tokenize(s: string): string[] {
  return s.match(/(\w+|\s+|[^\w\s])/g) ?? [];
}

function push(segs: WordSeg[], text: string, changed: boolean): void {
  const last = segs[segs.length - 1];
  if (last && last.changed === changed) last.text += text;
  else segs.push({ text, changed });
}

export function diffWords(a: string, b: string): { oldSegs: WordSeg[]; newSegs: WordSeg[] } {
  const at = tokenize(a);
  const bt = tokenize(b);
  const n = at.length;
  const m = bt.length;

  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] = at[i] === bt[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  const oldSegs: WordSeg[] = [];
  const newSegs: WordSeg[] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (at[i] === bt[j]) {
      push(oldSegs, at[i], false);
      push(newSegs, bt[j], false);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      push(oldSegs, at[i], true);
      i++;
    } else {
      push(newSegs, bt[j], true);
      j++;
    }
  }
  while (i < n) push(oldSegs, at[i++], true);
  while (j < m) push(newSegs, bt[j++], true);

  return { oldSegs, newSegs };
}
