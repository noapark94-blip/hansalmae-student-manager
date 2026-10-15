// Shared column flow for the editor, saved-paper viewer and browser printing.
export const EXAM_COLUMNS_CSS = `
.exam-columns{column-count:2;column-gap:8mm;column-rule:1px solid #d5cbd2;column-fill:balance;overflow-wrap:anywhere;orphans:3;widows:3}
.exam-columns article{break-inside:auto;page-break-inside:auto}
.exam-columns h2,.exam-columns article>header{break-after:avoid;page-break-after:avoid}
.exam-columns .passage{box-decoration-break:clone;-webkit-box-decoration-break:clone}
.exam-columns img{max-width:100%;height:auto;break-inside:avoid}
`;
