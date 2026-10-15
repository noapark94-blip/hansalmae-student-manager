export type PairedChoice = { mark: string; a: string; b: string };
const marks = "①②③④⑤⑥⑦⑧⑨⑩";
function cells(line: string) { return line.trim().replace(/^\|\s*/, "").replace(/\s*\|$/, "").split("|").map(cell => cell.trim()); }
export function isChoiceTableHeader(line: string) {
  const values = cells(line.replace(/\*\*/g, "")).filter(Boolean);
  return values.length === 2 && values[0] === "(A)" && values[1] === "(B)" || /^\s*\(A\)\s+\(B\)\s*$/.test(line.replace(/\*\*/g, ""));
}
export function isChoiceTableRule(line: string) { const values = cells(line); return values.length >= 2 && values.length <= 3 && values.every(value => /^:?-{3,}:?$/.test(value)); }
export function parsePairedChoices(value: string): PairedChoice[] | null {
  const rows: PairedChoice[] = [];
  for (const line of value.replace(/\r\n?/g, "\n").split("\n")) {
    if (!line.trim() || isChoiceTableHeader(line) || isChoiceTableRule(line)) continue;
    const raw = line.trim().replace(/^\|\s*/, "").replace(/\s*\|$/, "");
    const match = raw.match(/^([①②③④⑤⑥⑦⑧⑨⑩])\s*(?:\|\s*)?(.+)$/);
    if (!match) return null;
    const pair = match[2].split(/\s*\|\s*|\t+/).map(cell => cell.trim());
    if (pair.length !== 2 || pair.some(cell => !cell)) return null;
    rows.push({ mark: match[1], a: pair[0], b: pair[1] });
  }
  return rows.length >= 2 && rows.length <= 10 && rows.every((row, i) => row.mark === marks[i]) ? rows : null;
}
export function choiceTablePassage(passage: string, choices: string) {
  if (!parsePairedChoices(choices)) return passage;
  const lines = passage.split("\n");
  let header = lines.length - 1;
  while (header >= 0 && (!lines[header].trim() || isChoiceTableRule(lines[header]))) header--;
  return header >= 0 && isChoiceTableHeader(lines[header]) ? lines.slice(0, header).join("\n").trimEnd() : passage;
}
