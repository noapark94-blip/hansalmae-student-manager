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
  const columnsRoot = sheet.querySelector<HTMLElement>(".tt-columns");
  const columns = Array.from(columnsRoot?.querySelectorAll<HTMLElement>(".tt-column") ?? []);
  const footer = sheet.querySelector<HTMLElement>(".tt-page-footer");
  const outerHeight = (element: Element | null | undefined) => {
    if (!element) return 0;
    const style = getComputedStyle(element);
    return element.getBoundingClientRect().height + (parseFloat(style.marginTop) || 0) + (parseFloat(style.marginBottom) || 0);
  };
  const style = getComputedStyle(sheet);
  const padding = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
  const dayHeadingHeight = Math.max(0, ...columns.map(column => outerHeight(column.querySelector(".tt-day"))));
  const available = Math.max(30, height - padding - outerHeight(heading) - outerHeight(footer) - dayHeadingHeight - 8);
  const cards = columns.map(column => Array.from(column.querySelectorAll<HTMLElement>(".tt-card")));
  const heights = cards.map(items => items.map(outerHeight));
  const groups = heights.map(items => partitionTimetableRows(items, available));
  const count = Math.max(1, ...groups.map(pages => pages.length));
  const overflow = heights.some(items => items.some(h => h > available));
  const pages = Array.from({ length: count }, (_, i) => {
    const page = sheet.cloneNode(false) as HTMLElement;
    page.classList.add("tt-page");
    if (heading) page.append(heading.cloneNode(true));
    if (columnsRoot) {
      const pageColumns = columnsRoot.cloneNode(false) as HTMLElement;
      columns.forEach((column, day) => {
        const pageColumn = column.cloneNode(false) as HTMLElement;
        const dayHeading = column.querySelector(".tt-day");
        if (dayHeading) pageColumn.append(dayHeading.cloneNode(true));
        const body = sheet.ownerDocument.createElement("div"); body.className = "tt-day-cards";
        (groups[day][i] ?? []).forEach(index => body.append(cards[day][index].cloneNode(true)));
        pageColumn.append(body); pageColumns.append(pageColumn);
      });
      page.append(pageColumns);
    } else {
      const empty = sheet.querySelector(".tt-empty"); if (empty) page.append(empty.cloneNode(true));
    }
    const pageFooter = footer ? footer.cloneNode(true) as HTMLElement : sheet.ownerDocument.createElement("footer");
    pageFooter.classList.add("tt-page-footer");
    const number = sheet.ownerDocument.createElement("span");
    number.className = "tt-page-number"; number.textContent = `${i + 1} / ${count}`;
    pageFooter.append(number); page.append(pageFooter);
    return page.outerHTML;
  });
  return { source, pages, width, height, overflow };
}
