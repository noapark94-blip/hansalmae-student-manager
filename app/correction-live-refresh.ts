export type RefreshBatch = { full: boolean; assistants: boolean; ids: string[] };

/** Coalesce bursts and serialize reads. No interval polling or per-student waterfall. */
export function createCorrectionRefreshQueue(
  read: (batch: RefreshBatch) => Promise<void>,
  onError: (error: unknown) => void,
  options: { delay?: number; visible?: () => boolean } = {},
) {
  const delay = options.delay ?? 400;
  const visible = options.visible ?? (() => true);
  let full = false, assistants = false, running = false, disposed = false;
  const ids = new Set<string>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  function schedule(immediate = false) {
    if (disposed || running || timer || !visible() || (!full && !assistants && !ids.size)) return;
    timer = setTimeout(() => { timer = undefined; void flush(); }, immediate ? 0 : delay);
  }
  async function flush() {
    if (disposed || running || !visible()) return;
    const batch = { full, assistants, ids: [...ids] };
    full = false; assistants = false; ids.clear(); running = true;
    let failed = false;
    try { await read(batch); }
    catch (error) {
      failed = true; full = true;
      if (!disposed) onError(error);
    } finally {
      running = false;
      // Failed reads wait for reconnect, focus or another change; never spin.
      if (!failed) schedule();
    }
  }
  return {
    request(change: { full?: boolean; assistants?: boolean; id?: string } = {}, immediate = false) {
      if (disposed) return;
      full ||= !!change.full; assistants ||= !!change.assistants;
      if (change.id) ids.add(change.id);
      schedule(immediate);
    },
    dispose() { disposed = true; if (timer) clearTimeout(timer); },
  };
}

export function replaceChangedAssignments<T extends { id: string }, E extends { assignmentId: string }>(
  current: { assignments: T[]; exceptions: E[] },
  update: { assignments: T[]; exceptions: E[] },
  ids: string[],
) {
  const changed = new Set(ids);
  return {
    assignments: [...current.assignments.filter(row => !changed.has(row.id)), ...update.assignments],
    exceptions: [...current.exceptions.filter(row => !changed.has(row.assignmentId)), ...update.exceptions],
  };
}
