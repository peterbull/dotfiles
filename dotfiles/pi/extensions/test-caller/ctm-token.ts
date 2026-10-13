import {execFile} from 'node:child_process';
import {homedir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
export function ctmTokenProvider(accountId:number, accountSid:string, applicationSid:string, identity:string):()=>Promise<string> {
 if(!Number.isSafeInteger(accountId)||accountId<1||!/^AC[0-9a-f]{32}$/i.test(accountSid)||!/^AP[0-9a-f]{32}$/i.test(applicationSid)||!/^[a-z0-9_-]{1,64}$/i.test(identity))throw new Error('Invalid CTM dev token configuration.');
 return ()=>new Promise((resolve,reject)=>{
  execFile('mise',['exec','--','bundle','exec','rails','runner',join(dirname(fileURLToPath(import.meta.url)),'ctm-token.rb')],{
   cwd:join(homedir(),'work','ctm'),timeout:60000,maxBuffer:1024*1024,
   env:{...process.env,RAILS_ENV:'development',TEST_CALLER_CTM_ACCOUNT_ID:String(accountId),TEST_CALLER_ACCOUNT_SID:accountSid,TEST_CALLER_APPLICATION_SID:applicationSid,TEST_CALLER_IDENTITY:identity}
  },(error,stdout)=>{
   if(error){reject(new Error('Cannot sign with existing CTM dev Voice SDK key. Check the dev stack, account and dedicated application configuration.'));return;}
   const matches=stdout.match(/^TEST_CALLER_TOKEN=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/gm);
   if(matches?.length!==1){reject(new Error('CTM dev token helper returned no unique signed token.'));return;}
   resolve(matches[0].slice('TEST_CALLER_TOKEN='.length));
  });
 });
}
