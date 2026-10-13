// A minimal byte buffer for the bundled, offline signing algorithm.
const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
class Buffer extends Uint8Array {
  static from(value, encoding='utf8') {
    if(typeof value!=='string') return new Buffer(value);
    if(encoding==='hex') return new Buffer((value.match(/../g)||[]).map(v=>parseInt(v,16)));
    if(encoding==='base64') {
      const out=[]; let bits=0, count=0;
      for(const c of value){const n=chars.indexOf(c);if(n<0)continue;bits=(bits<<6)|n;count+=6;if(count>=8){count-=8;out.push((bits>>count)&255);}}
      return new Buffer(out);
    }
    const str=encoding==='ascii'?value:unescape(encodeURIComponent(value));return new Buffer(Array.from(str,c=>c.charCodeAt(0)));
  }
  static alloc(length,fill=0){const out=new Buffer(length);out.fill(fill);return out;}
  static concat(values){const out=new Buffer(values.reduce((n,v)=>n+v.length,0));let at=0;for(const v of values){out.set(v,at);at+=v.length;}return out;}
  copy(target,at=0,start=0,end=this.length){target.set(this.subarray(start,end),at);return end-start;}
  toString(encoding='utf8') {
    if(encoding==='hex')return Array.from(this,v=>v.toString(16).padStart(2,'0')).join('');
    if(encoding==='base64') {let out='';for(let i=0;i<this.length;i+=3){const n=(this[i]<<16)|((this[i+1]||0)<<8)|(this[i+2]||0);out+=chars[(n>>18)&63]+chars[(n>>12)&63]+(i+1<this.length?chars[(n>>6)&63]:'=')+(i+2<this.length?chars[n&63]:'=');}return out;}
    const str=Array.from(this,v=>String.fromCharCode(v)).join('');return encoding==='ascii'?str:decodeURIComponent(escape(str));
  }
  readUInt32LE(at=0){return (this[at]|(this[at+1]<<8)|(this[at+2]<<16)|(this[at+3]<<24))>>>0;}
  readUInt32BE(at=0){return ((this[at]<<24)|(this[at+1]<<16)|(this[at+2]<<8)|this[at+3])>>>0;}
  writeUInt32LE(v,at=0){for(let i=0;i<4;i++)this[at+i]=v>>>(8*i);return at+4;}
  writeUInt32BE(v,at=0){for(let i=0;i<4;i++)this[at+i]=v>>>(24-8*i);return at+4;}
  readBigUInt64LE(at=0){let n=0n;for(let i=7;i>=0;i--)n=(n<<8n)|BigInt(this[at+i]);return n;}
  writeBigUInt64LE(v,at=0){for(let i=0;i<8;i++)this[at+i]=Number((v>>BigInt(8*i))&255n);return at+8;}
  writeFloatLE(v,at=0){const bytes=new Uint8Array(new Float32Array([v]).buffer);this.set(bytes,at);return at+4;}
}
const crypto={createHash(algorithm){let input=Buffer.alloc(0);return{update(value){input=Buffer.concat([input,Buffer.from(value)]);return this;},digest(encoding){const out=Buffer.from(nativeHash(algorithm,input.toString('base64')),'base64');return encoding?out.toString(encoding):out;}};}};
