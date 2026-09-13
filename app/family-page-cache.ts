// Memory only: never persist student records to local/session storage.
type Entry = { value: unknown; savedAt: number };
type Bucket = { generation: number; entries: Map<string, Entry> };
const buckets = new WeakMap<object, Bucket>();
const MAX_AGE = 120_000;
const MAX_ENTRIES = 40;

export function clearFamilyPageCache(client: object) {
  const bucket = buckets.get(client);
  if (bucket) { bucket.generation++; bucket.entries.clear(); }
}

export function familyPageCache<T>(client: object, accountId: string, studentId: string | null, page: string) {
  let bucket = buckets.get(client);
  if (!bucket) { bucket = { generation: 0, entries: new Map() }; buckets.set(client, bucket); }
  const current = bucket;
  const generation = current.generation;
  const key = JSON.stringify([accountId, studentId, page]);
  return {
    valid: () => current.generation === generation,
    read(): T | null {
      if (current.generation !== generation) return null;
      const entry = current.entries.get(key);
      if (!entry) return null;
      if (Date.now() - entry.savedAt >= MAX_AGE) { current.entries.delete(key); return null; }
      return entry.value as T;
    },
    write(value: T) {
      if (current.generation !== generation) return;
      current.entries.delete(key);
      current.entries.set(key, { value, savedAt: Date.now() });
      while (current.entries.size > MAX_ENTRIES) current.entries.delete(current.entries.keys().next().value!);
    },
    clear() { if (current.generation === generation) current.entries.delete(key); },
  };
}

// Include the current month and the preceding six days when the week crosses a month.
export function familySummaryPeriod(today: string) {
  const weekStart = new Date(Date.parse(`${today}T00:00:00Z`) - 6 * 86400000).toISOString().slice(0, 10);
  return { start: [today.slice(0, 7) + "-01", weekStart].sort()[0], end: today, weekStart };
}
