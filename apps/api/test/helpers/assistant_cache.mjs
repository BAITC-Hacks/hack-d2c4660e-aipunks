export class MemoryAssistantCache {
  entries=new Map();requests=new Map();
  constructor(clock=Date.now){this.clock=clock;}
  async get(key){const e=this.entries.get(key);return e&&e.expires>this.clock()?structuredClone(e.value):null;}
  async putIfAbsent(key,value,ttl){const old=await this.get(key);if(old)return old;this.entries.set(key,{value:structuredClone(value),expires:this.clock()+ttl*1000});return structuredClone(value);}
  async rateLimit(uid,limit){const window=Math.floor(this.clock()/60000),old=this.requests.get(uid),entry=old?.window===window?old:{window,count:0};if(entry.count>=limit)return false;entry.count++;this.requests.set(uid,entry);return true;}
}
