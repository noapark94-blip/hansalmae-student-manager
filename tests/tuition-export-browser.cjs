const fs=require('node:fs'),assert=require('node:assert/strict'),esbuild=require('esbuild');
const {chromium}=require(process.env.HSM_PLAYWRIGHT_MODULE||'playwright');
(async()=>{
 const entry=`import React from 'react';import {createRoot} from 'react-dom/client';import {TuitionExportDialog} from './app/tuition-export-dialog';
 const a={id:'c1',studentId:'s1',studentName:'가상학생가',school:'테스트고',grade:'고1',subjects:['영어'],classNames:['고1 영어'],lineItems:[{className:'고등 영어',amount:350000}],totalAmount:350000,paidAmount:350000,status:'paid',memo:null,payments:[{id:'p1',amount:350000,method:'card',paidAt:'2026-09-30T16:00:00Z'}]};
 const b={...a,id:'c2',studentId:'s2',studentName:'가상학생나',school:'테스트중',grade:'중2',status:'open',paidAmount:0,payments:[]};
 window.fail=false;window.calls=[];const rpc=async(name,args)=>{window.calls.push([name,args]);return window.fail?{error:{message:'error'}}:{data:{isStaff:true,items:[{...a,id:args.p_month+'a'},{...b,id:args.p_month+'b'}]}}};
 const root=createRoot(document.getElementById('root'));window.render=()=>root.render(<TuitionExportDialog key={Math.random()} month="2026-10" rows={[a,b]} initialStudentIds={['s1']} supabase={{rpc}} onClose={()=>root.render(<p>닫힘</p>)}/>);window.render();`;
 await esbuild.build({stdin:{contents:entry,resolveDir:process.cwd(),loader:'tsx'},bundle:true,outfile:'/tmp/hsm-tuition-export.js',jsx:'automatic'});
 const css=fs.readFileSync('/tmp/hsm-tuition-export.css','utf8');fs.writeFileSync('/tmp/hsm-tuition-export.html',`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{box-sizing:border-box}body{font-family:Arial,sans-serif}${css}</style><div id="root"></div><script src="file:///tmp/hsm-tuition-export.js"></script></html>`);
 const browser=await chromium.launch({executablePath:process.env.HSM_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});const page=await browser.newPage({acceptDownloads:true});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('file:///tmp/hsm-tuition-export.html');
 for(const width of [390,1440]){await page.setViewportSize({width,height:1000});await page.evaluate(()=>window.render());await page.getByRole('dialog').waitFor();assert.equal(await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).count(),1);const box=await page.getByRole('dialog').boundingBox();assert.ok(box.x>=0&&box.x+box.width<=width);await page.screenshot({path:'/tmp/hsm-tuition-export-'+width+'.png'});}
 await page.getByRole('button',{name:'기간 내 전체 학생'}).click();assert.equal(await page.getByRole('button',{name:'선택한 2명 엑셀 저장'}).count(),1);
 await page.getByLabel('가상학생나',{exact:false}).uncheck();assert.equal(await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).count(),1);
 await page.getByLabel('시작월',{exact:true}).fill('2026-09');assert.equal(await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).isDisabled(),true);
 await page.getByRole('button',{name:'기간 적용'}).click();await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).waitFor();await page.waitForFunction(()=>window.calls.length===2);
 const download=page.waitForEvent('download');await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).click();const file=await download;assert.equal(file.suggestedFilename(),'원비목록_2026-09_2026-10.xlsx');await file.saveAs('/tmp/hsm-tuition-browser.xlsx');
 await page.getByRole('button',{name:'전체 해제',exact:true}).click();assert.equal(await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).isDisabled(),true);await page.getByRole('button',{name:'기본 항목'}).click();
 await page.evaluate(()=>window.fail=true);await page.getByRole('button',{name:'기간 적용'}).click();await page.getByRole('alert').waitFor();assert.equal(await page.getByRole('button',{name:'선택한 1명 엑셀 저장'}).isDisabled(),true);
 await page.evaluate(()=>window.fail=false);await page.getByRole('button',{name:'기간 적용'}).click();await page.getByRole('alert').waitFor({state:'detached'});
 await page.keyboard.press('Escape');await page.getByText('닫힘',{exact:true}).waitFor();assert.deepEqual(errors,[]);await browser.close();console.log('PASS mobile/desktop dialog, scope, exclusions across months, dirty range, download, empty columns, RPC failure/retry, escape, no console errors');
})().catch(e=>{console.error(e);process.exit(1)});
