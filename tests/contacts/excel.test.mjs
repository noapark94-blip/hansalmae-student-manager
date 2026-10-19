import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import ts from 'typescript';
import readXlsxFile from 'read-excel-file/node';
const require = createRequire(import.meta.url);
const m = {};
new Function('exports', 'require', ts.transpileModule(fs.readFileSync(new URL('../../app/contact-export-excel.ts', import.meta.url), 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(m, require);
test('Excel independently reads literal Korean names, roles and phone strings', async () => {
 const contacts = [{name:'서해고2 김민준 & <가족>',kind:'student',phone:'01012345678'}, {name:'=1+1 학부모',kind:'guardian',phone:'+821012345678'}];
 const rows = await readXlsxFile(Buffer.from(m.contactsExcel(contacts)));
 assert.deepEqual(rows, [['저장 이름','구분','전화번호'], ['서해고2 김민준 & <가족>','학생','01012345678'],['=1+1 학부모','학부모','+821012345678']]);
});
