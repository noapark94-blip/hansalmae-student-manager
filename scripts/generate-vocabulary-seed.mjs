import fs from "node:fs";
import path from "node:path";
import readXlsxFile from "read-excel-file/node";

const [source, output] = process.argv.slice(2);
if (!source || !output) throw new Error("usage: node scripts/generate-vocabulary-seed.mjs source.xlsx output.sql");
const mappings = [
  ["중등단어DB", "middle"],
  ["고등단어DB", "high"],
  ["수능단어DB", "csat"],
];
const q = (value) => `'${String(value ?? "").replaceAll("'", "''")}'`;
const statements = ["begin;", "truncate table public.vocabulary_words restart identity;"];
for (const [sheetName, slug] of mappings) {
  const rows = (await readXlsxFile(source, { sheet: sheetName })).slice(1)
    .filter((row) => Number(row[0]) > 0 && String(row[1]).trim());
  for (let start = 0; start < rows.length; start += 250) {
    const values = rows.slice(start, start + 250).map((row, index) => {
      const word = String(row[1]).trim();
      const answer = String(row[5] ?? "").trim() || word;
      return `((select id from public.vocabulary_word_sets where slug=${q(slug)}),${Number(row[0])},${q(word)},${q(String(row[2]).trim())},${q(String(row[3]).trim())},${q(String(row[4]).trim())},${q(answer)},${start + index + 1})`;
    });
    statements.push("insert into public.vocabulary_words(word_set_id,day,word,meaning,example,translation,example_answer,sort_order) values\n" + values.join(",\n") + ";");
  }
}
statements.push("commit;");
fs.writeFileSync(path.resolve(output), statements.join("\n\n"));
