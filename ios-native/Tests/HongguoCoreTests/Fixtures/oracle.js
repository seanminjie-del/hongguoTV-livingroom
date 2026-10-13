function oracle(row) {
  DEVICE=row.device;sessionNonce=row.nonce;sessionStarted=row.started;
  let seed=17;Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
  Date.now=()=>row.ts*1000;
  return buildMedusa(row.url,row.body===null?null:Buffer.from(row.body),row.ts);
}
