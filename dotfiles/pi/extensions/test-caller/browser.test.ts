import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const html=await readFile(new URL('./caller.html',import.meta.url),'utf8');
const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)![1];
function harness(){
 const elements=new Map(['start','hangup','state','error'].map(k=>[k,{disabled:false,textContent:'',onclick:undefined as any}]));
 const sources:any[]=[];const gains:any[]=[];const events:any[]=[];const destinations:any[]=[];let physicalMicCalls=0,deviceOptions:any;
 let processor:any, owned:any, connectWait:Promise<any>|undefined, decodeWait:Promise<any>|undefined;
 let now=Date.now(),watchdog:Function=()=>{};
 class Clock extends Date {static now(){return now;}}
 class AudioContext {
  async resume(){} async decodeAudioData(){return decodeWait ? await decodeWait : {duration:0.25};}
  createMediaStreamDestination(){const track={stopped:false,stop(){this.stopped=true;}};const destination={stream:{getTracks:()=>[track]}};destinations.push(destination);return destination;}
  createOscillator(){return {connect(){},start(){},stop(){}};}
  createGain(){const gain={gain:{value:1},connect(){}};gains.push(gain);return gain;}
  createBufferSource(){const source={buffer:null,connected:null as any,onended:null as any,stopped:false,connect(destination:any){this.connected=destination;},disconnect(){this.connected=null;},start(){},stop(){this.stopped=true;this.onended?.();}};sources.push(source);return source;}
 }
 class Call {
  parameters={CallSid:'CA'+'4'.repeat(32)};handlers=new Map<string,Function>();digits='';disconnected=false;
  constructor(privateInput:any){(this as any).input=privateInput;}
  on(name:string,handler:Function){this.handlers.set(name,handler);}status(){return 'pending';}
  sendDigits(digits:string){this.digits=digits;}disconnect(){this.disconnected=true;(this as any).input.getTracks().forEach((track:any)=>track.stop());void processor.destroyProcessedStream();this.handlers.get('disconnect')?.();}
 }
 class Device {
  constructor(_token:string,options:any){deviceOptions=options;}
  audio={addProcessor:async(p:any,remote:boolean)=>{assert.equal(remote,false);processor=p;}};
  on(){}updateToken(){}destroy(){}
  async connect(options:any){assert.ok(processor);assert.equal(JSON.stringify(options.params),'{}');const input=deviceOptions.getUserMedia?await deviceOptions.getUserMedia({audio:true}):await navigator.mediaDevices.getUserMedia({audio:true});await processor.createProcessedStream(input);owned=new Call(input);return connectWait ? await connectWait : owned;}
 }
 const navigator={mediaDevices:{getUserMedia:async(_constraints:any)=>{physicalMicCalls++;throw new Error('Physical microphone capture is forbidden in caller tests');}}};
 const context=vm.createContext({navigator,location:{hash:'#capability'},history:{replaceState(){}},document:{getElementById:(id:string)=>elements.get(id)},AudioContext,Twilio:{Device},Date:Clock,Error,JSON,AbortSignal,encodeURIComponent,setInterval:(fn:Function)=>{watchdog=fn;return 1;},clearInterval(){},setTimeout:()=>1,clearTimeout(){},window:{addEventListener(){}},fetch:async(path:string,options:any={})=>{
  if(path==='/api/event')events.push(JSON.parse(options.body));
  let body:any={};if(path==='/api/claim')body={lease:'lease',maxCallSeconds:180};if(path==='/api/token')body={token:'mock-token'};if(path==='/api/commands')body={commands:[]};
  return {ok:true,status:200,json:async()=>body,arrayBuffer:async()=>new ArrayBuffer(48)};
 }});
 vm.runInContext(script+'\nglobalThis.testApi={execute,hangup,LocalAudioProcessor,getState:()=>state};',context);
 return {context,elements,sources,gains,events,destinations,micCalls:()=>physicalMicCalls,deviceOptions:()=>deviceOptions,api:(context as any).testApi,owned:()=>owned,processor:()=>processor,delayConnect:(promise:Promise<any>)=>{connectWait=promise;},delayDecode:(promise:Promise<any>)=>{decodeWait=promise;},advance:(ms:number)=>{now+=ms;},watchdog:()=>watchdog()};
}
test('browser processor excludes physical microphone, plays only after connection, and hangup interrupts audio',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();
 await h.api.execute({id:'dial',action:'dial',payload:{}});
 assert.equal(h.gains[0].gain.value,0);assert.equal(h.sources.length,0);
 const call=h.owned();call.handlers.get('accept')!();
 assert.equal(h.api.getState().call_status,'connected');assert.equal(h.api.getState().call_sid,call.parameters.CallSid);
 const play=h.api.execute({id:'play',action:'play',payload:{audio_id:'issued'}});
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(h.sources.length,1);assert.ok(h.sources[0].connected);assert.equal(h.sources[0].connected.privateMicrophone,undefined);
 await h.api.execute({id:'hangup',action:'hangup',payload:{}});await play;
 assert.equal(h.sources[0].stopped,true);assert.equal(call.disconnected,true);assert.equal(h.api.getState().call_status,'disconnected');
 const receipt=h.events.find(e=>e.id==='play');assert.equal(receipt.result.status,'stopped');
});
test('browser DTMF whitelist and utterance replacement keep old endings from completing new playback',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();await h.api.execute({id:'dial',action:'dial',payload:{}});h.owned().handlers.get('accept')!();
 await h.api.execute({id:'bad',action:'digits',payload:{digits:'W'}});assert.equal(h.events.find(e=>e.id==='bad').ok,false);
 await h.api.execute({id:'ok',action:'digits',payload:{digits:'1w#'}});assert.equal(h.owned().digits,'1w#');
 const first=h.api.execute({id:'first',action:'play',payload:{audio_id:'one'}});await new Promise(resolve=>setImmediate(resolve));
 const oldEnd=h.sources[0].onended;
 const second=h.api.execute({id:'second',action:'play',payload:{audio_id:'two'}});await new Promise(resolve=>setImmediate(resolve));
 oldEnd();assert.equal(h.processor().active.source,h.sources[1]);h.sources[1].onended();await Promise.all([first,second]);
 assert.equal(h.events.find(e=>e.id==='first').result.status,'stopped');assert.equal(h.events.find(e=>e.id==='second').result.status,'completed');
 h.api.hangup();
});
test('hangup while SDK connection is pending disconnects the late owned call',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();let release!:(c:any)=>void;h.delayConnect(new Promise(resolve=>{release=resolve;}));
 const dial=h.api.execute({id:'pending',action:'dial',payload:{}});await new Promise(resolve=>setImmediate(resolve));
 const late=h.owned();h.api.hangup();release(late);await dial;
 assert.equal(late.disconnected,true);assert.equal(h.events.find(e=>e.id==='pending').ok,false);
});
test('stop during audio decoding prevents late playback; duplicate dial preserves the active call',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();await h.api.execute({id:'dial',action:'dial',payload:{}});h.owned().handlers.get('accept')!();
 const call=h.owned();await h.api.execute({id:'duplicate',action:'dial',payload:{}});assert.equal(call.disconnected,false);assert.equal(h.api.getState().call_status,'connected');
 let release!:(value:any)=>void;h.delayDecode(new Promise(resolve=>{release=resolve;}));
 const play=h.api.execute({id:'slow',action:'play',payload:{audio_id:'audio'}});await new Promise(resolve=>setImmediate(resolve));
 await h.api.execute({id:'stop',action:'stop_audio',payload:{}});release({duration:1});await play;
 assert.equal(h.sources.length,0);assert.equal(h.events.find(e=>e.id==='slow').result.status,'stopped');h.api.hangup();
});
test('independent watchdog hangs up despite a stalled controller poll',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();await h.api.execute({id:'dial',action:'dial',payload:{}});h.owned().handlers.get('accept')!();
 h.advance(6000);h.watchdog();assert.equal(h.owned().disconnected,true);assert.equal(h.api.getState().call_status,'disconnected');
});
test('SDK input uses a generated placeholder stream with no physical microphone request',async()=>{
 const h=harness();await h.elements.get('start')!.onclick();assert.equal(typeof h.deviceOptions().getUserMedia,'function');
 await h.api.execute({id:'dial',action:'dial',payload:{}});assert.equal(h.micCalls(),0);assert.equal(h.destinations.length,2);
 const placeholder=h.destinations[0].stream;const processed=h.destinations[1].stream;assert.notEqual(placeholder,processed);assert.equal(h.processor().destination.stream,processed);
 h.owned().handlers.get('accept')!();const play=h.api.execute({id:'speech',action:'play',payload:{audio_id:'issued'}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(h.sources[0].connected,h.destinations[1]);assert.equal(placeholder.getTracks()[0].stopped,false);assert.equal(processed.getTracks()[0].stopped,false);
 await h.api.execute({id:'hangup',action:'hangup',payload:{}});await play;assert.equal(placeholder.getTracks()[0].stopped,true);assert.equal(processed.getTracks()[0].stopped,true);assert.equal(h.events.find(e=>e.id==='speech').result.status,'stopped');assert.equal(h.micCalls(),0);
});
