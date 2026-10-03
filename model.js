export const modules = [
 ['IR','Internal Requisition','Department requests'],['PR','Purchase Requisition','Procurement requirements'],
 ['QUOTATION','Quotation','Vendor offers'],['PO','Purchase Order','Approved purchases'],
 ['DO','Delivery Order','Delivery records'],['GRN','Goods Received Note','Goods received'],
 ['INSPECTION','User Inspection','Acceptance and findings'],['INVOICE','Invoice / Submission','Invoices and submission tracking'],
 ['TCSC','TCSC','Separate register'],['GATE_PASS','Gate Pass','Returnable and non-returnable']
];
export const parentType={PR:'IR',QUOTATION:'PR',PO:'QUOTATION',DO:'PO',GRN:'DO',INSPECTION:'GRN',INVOICE:'INSPECTION'};
export const nextType=Object.fromEntries(Object.entries(parentType).map(([a,b])=>[b,a]));
export const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Karachi',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export function totals(items,tax=0){const subtotal=items.reduce((s,i)=>s+Number(i.qty)*Number(i.rate),0);return {subtotal,tax:subtotal*Number(tax)/100,total:subtotal*(1+Number(tax)/100)};}
export function validate(doc){
 if(!modules.some(m=>m[0]===doc.type))throw Error('Invalid document type');
 if(!doc.title?.trim()||!doc.department?.trim())throw Error('Title and department are required.');
 if(!doc.date)throw Error('Document date is required.');
 if(!doc.items?.length)throw Error('Add at least one item.');
 for(const i of doc.items){if(!i.description?.trim()||!Number.isFinite(Number(i.qty))||Number(i.qty)<=0||!Number.isFinite(Number(i.rate))||Number(i.rate)<0)throw Error('Every item needs a description, positive quantity and non-negative rate.');}
 if(!Number.isFinite(Number(doc.tax))||Number(doc.tax)<0||Number(doc.tax)>100)throw Error('Tax must be between 0 and 100.');
 if(parentType[doc.type]&&!doc.parent_id)throw Error('Select an approved source document.');
 if(['QUOTATION','PO','INVOICE'].includes(doc.type)&&!doc.party?.trim())throw Error('Vendor / party is required.');
 if(doc.type==='GATE_PASS'&&doc.extra?.pass_type==='Returnable'&&!doc.extra?.expected_return)throw Error('Expected return date is required.');
 if(doc.type==='INSPECTION'&&!['Accepted','Rejected','Partially accepted'].includes(doc.extra?.result))throw Error('Select an inspection result.');
 return true;
}
export function canEdit(doc,profile){return ['Draft','Rejected'].includes(doc.status)&&(profile.role==='admin'||doc.created_by===profile.id);}
export function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
export function csv(rows){return rows.map(row=>row.map(v=>{let s=String(v??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}).join(',')).join('\r\n');}

export const hasPricing = type => ['QUOTATION','PO','INVOICE'].includes(type);
export const quantityLabel = type => ({IR:'Required quantity',PR:'Requested quantity',DO:'Delivered quantity',GRN:'Received quantity',INSPECTION:'Inspected quantity',GATE_PASS:'Movement quantity'})[type] || 'Quantity';
