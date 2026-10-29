import {strToU8,zipSync} from 'fflate';
import {amounts,exportColumns,exportValue,paymentRows,type ColumnKey,type ExportEntry} from './tuition-export-model';
const xml=(v:string)=>v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g,'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const rel='http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const declaration='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const moneyKeys=new Set<ColumnKey>(['total','paid','waived','balance']);
function cell(value:string|number|null,col:number,row:number,style=0){const ref=String.fromCharCode(65+col)+row;return value===null?`<c r="${ref}" s="${style}"/>`:typeof value==='number'?`<c r="${ref}" s="${style}"><v>${value}</v></c>`:`<c r="${ref}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;}
/** Numeric dates use the Excel 1900 epoch; all user text is literal, never a formula. */
export function tuitionExcel(entries:ExportEntry[],keys:ColumnKey[]):Uint8Array<ArrayBuffer>{
 const columns=exportColumns.filter(c=>keys.includes(c[0]));
 if(!columns.length||!entries.length)throw new Error('내보낼 항목과 학생을 선택해 주세요.');
 const months=[...new Set(entries.map(r=>r.month))].sort();
 const files:Record<string,string>={};
 months.forEach((month,index)=>{
  const selected=entries.filter(r=>r.month===month).sort((a,b)=>a.studentName.localeCompare(b.studentName,'ko'));
  const dataRows=selected.flatMap(row=>paymentRows(row).map((p,i)=>columns.map(([key])=>exportValue(row,key,p,i===0))));
  const last=String.fromCharCode(64+columns.length),end=dataRows.length+4;
  const totals=selected.reduce((a,r)=>{const x=amounts(r);return {total:a.total+x.total,paid:a.paid+x.paid,waived:a.waived+x.waived,balance:a.balance+x.balance};},{total:0,paid:0,waived:0,balance:0});
  const rows=[`<row r="1" ht="30" customHeight="1">${cell(`${month} 원비 목록`,0,1)}</row>`,
   `<row r="2" ht="40" customHeight="1">${cell('귀속월 기준 · 단위: 원 · 면제액은 미납에서 제외 · 분할 납부는 건별 표시(원비·면제·미납은 첫 행에만 표시)',0,2)}</row>`,
   `<row r="3" ht="28" customHeight="1">${columns.map(([key],i)=>moneyKeys.has(key)?`<c r="${String.fromCharCode(65+i)}3" s="2"><f>SUM(${String.fromCharCode(65+i)}5:${String.fromCharCode(65+i)}${end})</f><v>${totals[key as keyof typeof totals]}</v></c>`:cell(i===0?`합계 (${selected.length}명)`:'',i,3)).join('')}</row>`,
   `<row r="4" ht="28" customHeight="1">${columns.map(([,label],i)=>cell(label,i,4,1)).join('')}</row>`,
   ...dataRows.map((values,i)=>`<row r="${i+5}" ht="42" customHeight="1">${values.map((v,j)=>cell(v,j,i+5,columns[j][0]==='date'?3:moneyKeys.has(columns[j][0])?2:0)).join('')}</row>`)
  ];
  files[`xl/worksheets/sheet${index+1}.xml`]=`<worksheet xmlns="${ns}"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:${last}${end}"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="30"/><cols>${columns.map((c,i)=>`<col min="${i+1}" max="${i+1}" width="${c[2]}" customWidth="1"/>`).join('')}</cols><sheetData>${rows.join('')}</sheetData><autoFilter ref="A4:${last}${end}"/>${columns.length>1?`<mergeCells count="2"><mergeCell ref="A1:${last}1"/><mergeCell ref="A2:${last}2"/></mergeCells>`:''}<pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>`;
 });
 files['[Content_Types].xml']=`<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${months.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}</Types>`;
 files['_rels/.rels']=`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>`;
 files['xl/workbook.xml']=`<workbook xmlns="${ns}" xmlns:r="${rel}"><workbookPr date1904="0"/><sheets>${months.map((m,i)=>`<sheet name="${m}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')}</sheets><calcPr fullCalcOnLoad="1"/></workbook>`;
 files['xl/_rels/workbook.xml.rels']=`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${months.map((_,i)=>`<Relationship Id="rId${i+1}" Type="${rel}/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join('')}<Relationship Id="rId${months.length+1}" Type="${rel}/styles" Target="styles.xml"/></Relationships>`;
 files['xl/styles.xml']=`<styleSheet xmlns="${ns}"><numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd"/></numFmts><fonts count="2"><font><sz val="11"/><name val="맑은 고딕"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="맑은 고딕"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF784563"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4">${[0,1,2,3].map(i=>`<xf numFmtId="${i===2?164:i===3?165:0}" fontId="${i===1?1:0}" fillId="${i===1?2:0}" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="center" horizontal="${i===1?'center':i>1?'right':'left'}" wrapText="1"/></xf>`).join('')}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
 return new Uint8Array(zipSync(Object.fromEntries(Object.entries(files).map(([p,s])=>[p,strToU8(declaration+s)])),{level:6}));
}
