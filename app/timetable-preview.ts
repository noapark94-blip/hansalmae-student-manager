export type TimetablePreview = { source: string; pages: string[]; width: number; height: number; overflow: boolean };
export function fitTimetableScale(viewportWidth: number, paperWidth: number) {
  if (viewportWidth <= 0 || paperWidth <= 0) return 1;
  return Math.max(0.05, Math.min(1, (viewportWidth - 32) / paperWidth));
}
export function partitionTimetableRows(heights: number[], available: number): number[][] {
  const pages: number[][] = []; let current: number[] = [], used = 0;
  heights.forEach((height, index) => {
    if (current.length && used + height > available) { pages.push(current); current = []; used = 0; }
    current.push(index); used += height;
  });
  if (current.length) pages.push(current);
  return pages.length ? pages : [[]];
}
export function paginateTimetableElement(sheet: HTMLElement, source: string): TimetablePreview {
  const width = sheet.getBoundingClientRect().width, height = width * 210 / 297;
  const heading = sheet.querySelector<HTMLElement>(".tt-heading");
  const table = sheet.querySelector<HTMLTableElement>("table");
  const footer = sheet.querySelector<HTMLElement>(".tt-page-footer");
  const head = table?.querySelector("thead");
  const rows = Array.from(table?.querySelectorAll<HTMLTableRowElement>("tbody > tr") ?? []);
  const outerHeight = (element: Element | null | undefined) => {
    if (!element) return 0;
    const style = getComputedStyle(element);
    return element.getBoundingClientRect().height + (parseFloat(style.marginTop) || 0) + (parseFloat(style.marginBottom) || 0);
  };
  const style = getComputedStyle(sheet);
  const padding = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
  const available = Math.max(30, height - padding - outerHeight(heading) - outerHeight(footer) - outerHeight(head) - 8);
  const heights = rows.map(row => row.getBoundingClientRect().height);
  const groups = partitionTimetableRows(heights, available);
  const overflow = heights.some(h => h > available);
  const pages = groups.map((indices, i) => {
    const page = sheet.cloneNode(false) as HTMLElement;
    page.classList.add("tt-page");
    if (heading) page.append(heading.cloneNode(true));
    if (table && head) {
      const pageTable = table.cloneNode(false) as HTMLTableElement;
      pageTable.append(head.cloneNode(true));
      const body = sheet.ownerDocument.createElement("tbody");
      indices.forEach(index => body.append(rows[index].cloneNode(true)));
      pageTable.append(body); page.append(pageTable);
    } else {
      const empty = sheet.querySelector(".tt-empty"); if (empty) page.append(empty.cloneNode(true));
    }
    const pageFooter = footer ? footer.cloneNode(true) as HTMLElement : sheet.ownerDocument.createElement("footer");
    pageFooter.classList.add("tt-page-footer");
    const number = sheet.ownerDocument.createElement("span");
    number.className = "tt-page-number"; number.textContent = `${i + 1} / ${groups.length}`;
    pageFooter.append(number); page.append(pageFooter);
    return page.outerHTML;
  });
  return { source, pages, width, height, overflow };
}
