/** Keep the first entry for each English word, including its meaning/example. */
export function deduplicateVocabulary<T extends { word: string }>(words: T[]) {
  const seen = new Set<string>();
  const unique: T[] = [];
  const excluded: T[] = [];
  for (const item of words) {
    const key = item.word.trim().replace(/\s+/g, " ").toLowerCase();
    if (key && seen.has(key)) excluded.push(item);
    else {
      if (key) seen.add(key);
      unique.push(item);
    }
  }
  return { unique, excluded };
}
