const fs=require('node:fs'),assert=require('node:assert/strict'),esbuild=require('esbuild');
const {chromium}=require(process.env.HSM_PLAYWRIGHT_MODULE||'playwright');
(async()=>{
 const entry=`import React from 'react';import {createRoot} from 'react-dom/client';import {TuitionBoard} from './app/tuition-board';
 const items=[600000,270000,270000,250000,270000,250000].map((amount,i)=>({id:'c'+i,studentId:'s'+i,studentName:'테스트학생'+i,school:'테스트고',grade:'고1',subjects:['영어'],classNames:['영어반'],classes:'영어반',lineItems:[{className:'영어',amount}],baseAmount:amount,discountAmount:0,additionalAmount:0,totalAmount:amount,paidAmount:0,balance:amount,status:i>=4?'waived':'open',memo:null,payments:[]}));
 createRoot(document.getElementById('root')).render(<TuitionBoard supabase={{from:()=>({select:()=>({eq:()=>({order:async()=>({data:[]})})})}),rpc:async(name)=>{if(name!=='tuition_board')throw Error('Unexpected request');return {data:{isStaff:true,items}}}}}/>);`;
 await esbuild.build({stdin:{contents:entry,resolveDir:process.cwd(),loader:'tsx'},bundle:true,outfile:'/tmp/hsm-waived.js',jsx:'automatic',plugins:[{name:'image-stub',setup(build){build.onResolve({filter:/^next\/image$/},()=>({path:'image',namespace:'stub'}));build.onLoad({filter:/.*/,namespace:'stub'},()=>({contents:'export default function Image(){return null}',loader:'js'}));}}]});
 fs.writeFileSync('/tmp/hsm-waived.html','<!doctype html><meta charset="utf-8"><div id="root"></div><script src="file:///tmp/hsm-waived.js"></script>');
 const browser=await chromium.launch({executablePath:process.env.HSM_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('file:///tmp/hsm-waived.html');await page.locator('.tuition-row').first().waitFor();
 assert.match(await page.locator('.tuition-summary .outstanding').textContent(),/1,390,000원/);
 assert.match(await page.locator('.tuition-summary .attention').textContent(),/4명/);
 assert.match(await page.locator('.tuition-summary article').first().textContent(),/면제 520,000원 포함/);
 const waived=page.locator('.tuition-row.waived');assert.equal(await waived.count(),2);
 for(let i=0;i<2;i++){assert.equal(await waived.nth(i).locator(':scope > strong').nth(2).textContent(),'0원');assert.equal(await waived.nth(i).locator('strong.balance').count(),0);}
 await waived.first().getByRole('button',{name:'납부 관리',exact:true}).click();assert.match(await page.locator('.payment-manager-totals').textContent(),/미수금0원/);
 assert.deepEqual(errors,[]);await browser.close();console.log('PASS: actual tuition board excludes waived 520,000 from total, rows, order and payment details; four outstanding students total 1,390,000');
})().catch(e=>{console.error(e);process.exit(1)});
