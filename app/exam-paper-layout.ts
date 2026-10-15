// Shared column flow for the editor, saved-paper viewer and browser printing.
export const EXAM_COLUMNS_CSS = `
.exam-columns{column-count:2;column-gap:8mm;column-rule:1px solid #d5cbd2;column-fill:balance;overflow-wrap:anywhere;orphans:3;widows:3}
.exam-columns article{break-inside:auto;page-break-inside:auto}
.exam-columns h2,.exam-columns article>header{break-after:avoid;page-break-after:avoid}
.exam-columns .passage{box-decoration-break:clone;-webkit-box-decoration-break:clone}
.exam-columns img{max-width:100%;height:auto;break-inside:avoid}
.exam-columns article:has(>.exam-choice-table){break-inside:avoid;page-break-inside:avoid}
.exam-choice-table{border-collapse:collapse;table-layout:fixed;width:100%;margin:3mm 0 4mm;font-size:inherit;line-height:1.55;white-space:normal;break-inside:avoid;page-break-inside:avoid}.exam-choice-table .exam-choice-mark{width:7mm}.exam-choice-table th,.exam-choice-table td{border:0;background:transparent;padding:1.1mm 1.5mm;vertical-align:top;text-align:left;overflow-wrap:anywhere;word-break:normal}.exam-choice-table thead th{border-bottom:1px solid #b8acb4;font-weight:700;padding-bottom:1.5mm}.exam-choice-table tbody th{font-weight:400;width:7mm;padding-left:0;text-align:center}.exam-choice-table tr{break-inside:avoid}.exam-choice-table thead{display:table-header-group}.exam-sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
`;
