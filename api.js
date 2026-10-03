import {today,validate,parentType,canEdit} from './model.js';
const cfg=window.TELEC_CONFIG;
export const configured=!!(cfg.supabaseUrl&&cfg.supabaseKey);
let demo=false,session=null,profile=null;
const DEMOKEY='telec-procurement-demo-v1';
function db(){return JSON.parse(localStorage.getItem(DEMOKEY)||'{"docs":[],"events":[],"profiles":[{"id":"demo-admin","name":"Demo Administrator","email":"demo@telec.local","role":"admin","active":true}]}');}
function save(data){localStorage.setItem(DEMOKEY,JSON.stringify(data));}
export function isDemo(){return demo;}
export function currentProfile(){return profile;}
async function request(path,{method='GET',body,auth=true}={}){
 if(auth&&session&&session.expires_at<Date.now()/1000+60){const refreshed=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},auth:false});setSession(refreshed);}
 const r=await fetch(cfg.supabaseUrl.replace(/\/$/,'')+path,{method,headers:{apikey:cfg.supabaseKey,'Content-Type':'application/json',Authorization:'Bearer '+(auth&&session?session.access_token:cfg.supabaseKey),Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let out;try{out=raw?JSON.parse(raw):null;}catch{throw Error('Unexpected server response.');}
 if(!r.ok)throw Error(out?.msg||out?.message||out?.error_description||out?.error||'Request failed');return out;
}
function setSession(s){session={...s,expires_at:s.expires_at||Date.now()/1000+s.expires_in};sessionStorage.setItem('telec-session',JSON.stringify(session));}
export async function login(email,password){demo=false;setSession(await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password},auth:false}));await loadProfile();}
async function loadProfile(){profile=(await request('/rest/v1/profiles?id=eq.'+encodeURIComponent(session.user.id)))[0];if(!profile?.active){session=null;sessionStorage.removeItem('telec-session');throw Error('Your account requires administrator activation.');}}
export async function restore(){if(!configured)return false;try{session=JSON.parse(sessionStorage.getItem('telec-session')||'null');if(!session)return false;await loadProfile();return true;}catch{session=null;sessionStorage.removeItem('telec-session');return false;}}
export function startDemo(){demo=true;const d=db();if(d.profiles.length===1){d.profiles.push({id:'demo-approver',name:'Demo Approver',email:'approver@telec.local',role:'approver',active:true});save(d);}profile=d.profiles[0];}
export function switchDemo(){if(demo){const p=db().profiles;profile=p.find(x=>x.id!==profile.id);}}
export async function logout(){try{if(!demo&&session)await request('/auth/v1/logout',{method:'POST'});}finally{session=null;profile=null;demo=false;sessionStorage.removeItem('telec-session');}}
export async function list(){return demo?db().docs:await request('/rest/v1/documents?select=*&order=created_at.desc&limit=5000');}
export async function events(id){return demo?db().events.filter(e=>e.document_id===id):await request('/rest/v1/document_events?document_id=eq.'+id+'&order=created_at.asc');}
export async function users(){return demo?db().profiles:await request('/rest/v1/profiles?order=name');}
export async function updateUser(id,role,active){if(demo){const d=db();if(id===profile.id)throw Error('You cannot change your own role.');Object.assign(d.profiles.find(p=>p.id===id),{role,active});save(d);return;}await request('/rest/v1/rpc/set_user_access',{method:'POST',body:{p_user:id,p_role:role,p_active:active}});}
export async function persist(doc,id){validate(doc);if(demo){const data=db();if(parentType[doc.type]){const p=data.docs.find(d=>d.id===doc.parent_id);if(!p||p.type!==parentType[doc.type]||p.status!=='Approved'||p.company!==doc.company)throw Error('An approved source in the same company is required.');if(p.type==='INSPECTION'&&p.extra.result==='Rejected')throw Error('Rejected inspection cannot be invoiced.');}
 const old=data.docs.find(d=>d.id===id);if(old&&!canEdit(old,profile))throw Error('Document cannot be edited.');const d={...doc,id:id||crypto.randomUUID(),status:old?.status||'Draft',created_by:old?.created_by||profile.id,created_at:old?.created_at||new Date().toISOString(),updated_at:new Date().toISOString(),number:old?.number||`${doc.type}-${new Date().getFullYear()}-${String(data.docs.length+1).padStart(5,'0')}`};if(old)data.docs[data.docs.indexOf(old)]=d;else data.docs.unshift(d);data.events.push({id:crypto.randomUUID(),document_id:d.id,actor:profile.name,action:old?'Edited':'Created',note:'',created_at:new Date().toISOString()});save(data);return d;}
 const payload={...doc};return (await request('/rest/v1/documents'+(id?'?id=eq.'+id:''),{method:id?'PATCH':'POST',body:payload}))[0];}
export async function transition(id,status,note){if(demo){const data=db(),d=data.docs.find(d=>d.id===id);const valid=(['Draft','Rejected'].includes(d.status)&&status==='Pending')||(d.status==='Pending'&&['Approved','Rejected'].includes(status))||(d.type==='INVOICE'&&d.status==='Approved'&&status==='Submitted')||(d.type==='GATE_PASS'&&d.status==='Approved'&&status==='Issued')||(d.type==='GATE_PASS'&&d.status==='Issued'&&d.extra.pass_type==='Returnable'&&status==='Returned');if(!valid)throw Error('Invalid status transition.');if(['Approved','Rejected','Issued','Returned'].includes(status)&&!['admin','approver'].includes(profile.role))throw Error('Approver role required.');if(['Approved','Rejected'].includes(status)&&d.created_by===profile.id)throw Error('Another approver must review your document.');if(status==='Pending'&&d.created_by!==profile.id&&profile.role!=='admin')throw Error('Owner or administrator required.');if(['Rejected','Submitted','Returned','Issued'].includes(status)&&!note.trim())throw Error('Please enter the required note.');d.status=status;d.updated_at=new Date().toISOString();data.events.push({id:crypto.randomUUID(),document_id:id,actor:profile.name,action:status,note,created_at:new Date().toISOString()});save(data);return;}
 await request('/rest/v1/rpc/transition_document',{method:'POST',body:{p_id:id,p_status:status,p_note:note}});}
export async function changePassword(password){if(demo)throw Error('Password changes are unavailable in demo.');if(password.length<8)throw Error('Use at least 8 characters.');await request('/auth/v1/user',{method:'PUT',body:{password}});}
export function resetDemo(){localStorage.removeItem(DEMOKEY);}
