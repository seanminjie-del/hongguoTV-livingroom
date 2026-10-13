// SPDX-License-Identifier: GPL-3.0-only
// Development-only independent signature fixtures; not bundled into the APK.
const fs=require('fs'),vm=require('vm'),path=require('path');
// Use app-source.js from jackotom/hongguo-drama commit 5a12c8840ec54fe1a7b10d0519cf64b4875b1983.
const src=process.argv[2];
if(!src) throw new Error('Pass the path to the pinned app-source.js');
const source=fs.readFileSync(src,'utf8');
const result=[];
for(let variant=0;variant<12;variant++) {
 const ts=1800500000+variant,nonce='test-only-visitor-nonce',started=ts*1000;
 const crypto=require('crypto');
 const ctx=vm.createContext({require:p=>p==='node:crypto'?{...crypto,randomBytes:n=>Buffer.alloc(n)}:require(path.resolve(path.dirname(src),p)),Buffer,module:{exports:{}}});
 vm.runInContext(`Date.now=()=>${started};`,ctx);
 vm.runInContext(source.replace("const PROCESS_NONCE = crypto.randomBytes(18).toString('base64url');",`const PROCESS_NONCE = '${nonce}';`)+`;globalThis.oracle={branchOf,buildMedusa};`,ctx);
 const body=variant%2===0?Buffer.from('{"video":"1234567890"}'):null;
 const device={device_id:'1000123456789012',version_name:'7.1.3.32'};
 let url;for(let ticket=0;ticket<128;ticket++){url=`https://example.com/api?device_id=${device.device_id}&q=${encodeURIComponent('短剧')}&ticket=${ticket}`;if(ctx.oracle.branchOf(url,body,ts)===0)break;}
 vm.runInContext('let seed=17;Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};',ctx);
 result.push({ts,url,body:body?.toString()??null,device,nonce,started,medusa:ctx.oracle.buildMedusa(url,body,ts,device)});
}
fs.writeFileSync(path.join(__dirname,'../core/src/test/resources/visitor-signing.json'),JSON.stringify(result,null,2)+'\n');
