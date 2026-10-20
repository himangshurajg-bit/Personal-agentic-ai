// Run against a scratch database only: creates 26 synthetic notes, never external actions.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
(async()=>{
const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
try {
 const errors=[];let checks=0;
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(process.env.UI_URL || 'http://127.0.0.1:8765/');
 const marker='Notebook UI '+Date.now();
 await page.evaluate(async marker=>{
   for(let i=0;i<25;i++){
     const response=await fetch('/api/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({request:'remember '+marker+' École '+i})});
     if(!response.ok)throw Error('Seeding failed');
   }
   await fetch('/api/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({request:'remember '+marker+' <img src=x onerror="window.notebookXss=true">'})});
 },marker);
 await page.getByLabel('Filter saved notes').fill(marker);
 await page.getByRole('button',{name:'Browse notes',exact:true}).click();
 await page.locator('#notes-output .match').nth(19).waitFor();
 assert.equal(await page.locator('#notes-output .match').count(),20);checks++;
 assert.equal(await page.locator('#notes-output img').count(),0);
 assert.equal(await page.evaluate(()=>window.notebookXss),undefined);checks++;
 const first=await page.locator('#notes-output strong').allTextContents();
 await page.getByRole('button',{name:'Next page',exact:true}).click();
 await page.getByText('6 notes on this page',{exact:true}).waitFor();
 const last=await page.locator('#notes-output strong').allTextContents();
 assert.equal(last.length,6);assert.equal(new Set([...first,...last]).size,26);checks++;
 assert.equal(await page.locator('#notes-more').isHidden(),true);checks++;
 await page.getByLabel('Filter saved notes').fill(marker+' e\u0301COLE');
 await page.getByRole('button',{name:'Browse notes',exact:true}).click();
 await page.locator('#notes-output .match').nth(19).waitFor();
 assert.equal(await page.locator('#notes-output .match').count(),20);checks++;
 await page.getByLabel('Filter saved notes').fill(marker+' missing');
 await page.getByRole('button',{name:'Browse notes',exact:true}).click();
 await page.getByText('No notes match this filter.',{exact:false}).waitFor();
 assert.equal(await page.locator('#notes-more').isHidden(),true);checks++;
 await page.getByLabel('Filter saved notes').fill(marker+' école');
 await page.getByRole('button',{name:'Browse notes',exact:true}).click();
 await page.locator('#notes-output .match').nth(19).waitFor();
 const out=process.env.UI_SCREENSHOTS || '/tmp/notebook-ui-screens';fs.mkdirSync(out,{recursive:true});
 await page.locator('.notebook').screenshot({path:path.join(out,'notebook-desktop.png')});checks++;
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);checks++;
 await page.getByRole('button',{name:'Next page',exact:true}).click();
 await page.getByText('5 notes on this page',{exact:true}).waitFor();checks++;
 await page.locator('.notebook').screenshot({path:path.join(out,'notebook-mobile.png')});
 await page.emulateMedia({reducedMotion:'reduce'});
 assert.equal(await page.evaluate(()=>getComputedStyle(document.querySelector('.hero-drop')).animationName),'none');checks++;
 assert.deepEqual(errors,[]);checks++;
 console.log(JSON.stringify({checks,errors,desktop:'1440x1000',mobileEmulated:'390x844'},null,2));
} finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
