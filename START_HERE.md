# TELEC Procurement ERP

## Included modules

Internal Requisition → Purchase Requisition → Quotation → Purchase Order → Delivery Order → Goods Received Note → User Inspection → Invoice / Submission.

Separate registers: TCSC and Gate Pass.

Features: linked source documents, multiple vendor quotations per PR, draft editing, submit/approve/reject, rejection remarks, document numbers, item quantities and rates, tax totals, activity history, A4 print/Save PDF, CSV export, JSON records export, admin/approver/user access, returnable/non-returnable gate passes, overdue returns, three-company selection and responsive screens.

TCSC is currently a separate general register with category, reference, responsible person, items and notes. Confirm its full form, required fields and approval procedure before using it for official work.

## Sab se pehle

1. ZIP extract karein.
2. GitHub par new repository banayein. Public ya private aap ki choice hai. Passwords, secret API keys aur company exports repository mein upload na karein.
3. Extracted `TELEC_Procurement_ERP` folder ke **andar wali files** GitHub repository ki root mein upload karein. Root mein `index.html`, `app.js`, `config.js` aur `supabase` folder nazar aana chahiye.

## Supabase setup

1. Supabase mein new project banayein. Is SQL ko new project mein run karein, kisi purane ERP database mein bina review ke nahi.
2. SQL Editor → New query. `supabase/schema.sql` ki poori script paste karke Run karein. Sirf ek baar run karna hai.
3. Authentication → Users → Add user. Apna email aur password set karein, email confirm karein.
4. `supabase/bootstrap_admin.sql` mein `YOUR_EMAIL_HERE` ko apne exact email se replace karein. SQL Editor mein run karein.
5. Authentication → Users mein second account banayein. ERP mein admin sign in karke **User access** mein usay `approver` aur Active set karein. Apna document khud approve nahi kar sakte.
6. Supabase project URL aur **publishable key / legacy anon key** copy karein. `config.js` mein:

```js
window.TELEC_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseKey: 'YOUR_PUBLISHABLE_OR_ANON_KEY',
  company: 'TELEC Electronics & Machinery (Pvt.) Ltd.',
  address: 'Apna complete office address yahan likhein',
  currency: 'PKR'
};
```

**Service role / secret key kabhi config.js mein na lagayein.** Public key browser mein visible hoti hai; data access Supabase authentication, RLS policies aur database functions se control hota hai.

7. Updated `config.js` GitHub mein save/commit karein.

## Vercel par live karna

1. Vercel → Add New → Project → GitHub repository Import.
2. Framework preset: **Other**.
3. Root Directory: repository root, agar files root mein upload ki hain. Agar poora folder upload hua hai to `TELEC_Procurement_ERP` select karein.
4. Build Command: blank / override enabled with empty value. Output Directory: blank. Install Command: blank. Is app ko dependency install/build ki zaroorat nahi.
5. Deploy karein. URL open karke apne admin email/password se sign in karein.
6. Supabase Authentication → URL Configuration mein Site URL ko Vercel URL set karein. Is release mein password reset email flow shamil nahi; user creation/recovery Supabase admin se manage hoti hai.

Official references:
- https://supabase.com/docs/guides/api
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/auth/passwords
- https://vercel.com/docs/git

## Pehli entry ka flow

1. User IR mein department, title, items, quantity, rates aur notes enter karke draft save kare.
2. Submit for approval. Doosra active admin/approver approve ya reason ke saath reject kare.
3. Approved record open karein → Create next document. Items copy ho jayenge, phir draft mein edit kar sakte hain.
4. PR se vendor quotations alag alag create ho sakti hain. Chosen approved quotation se PO banayein.
5. DO → GRN → Inspection. Accepted / Partially accepted inspection approve hone ke baad Invoice create ho sakti hai. Rejected inspection se invoice blocked hai.
6. Invoice approve hone ke baad Record submission mein date, recipient aur acknowledgment reference likhein. Ye audit history mein save hota hai.
7. Gate Pass alag banayein → Submit → Approve → Issue. Returnable pass mein expected return zaroor enter karein. Wapas aane par Record return karein.
8. Print / Save PDF button se A4 print ya browser Save as PDF use karein.

## Roles

| Role | Access |
| --- | --- |
| User | All active-company records read; own Draft/Rejected documents edit and submit; own approved invoice submission record |
| Approver | User access plus others' documents approve/reject, approved invoice submission and gate pass issue/return |
| Admin | Approver access plus user activation/roles and any Draft/Rejected document edit/submit |

All active staff can view all three companies' documents. Company dropdown is a record label, not a company-level security boundary. Approved documents are immutable. Self approval is blocked for every role. Account deletion, document deletion and manual audit editing are not exposed.

## Demo / local preview

Vercel par config blank ho to Explore demo available hai. Demo data sirf us browser mein rahega. Demo user / approver switch karke approval cycle check karein. Demo ko live database mein automatically import nahi kiya jata.

Local computer par Python installed ho to folder ke andar terminal mein:

```bash
python -m http.server 3000
```

Phir `http://localhost:3000` open karein. `index.html` double-click se ES modules reliably load nahi hote. GitHub/Vercel wala route simpler hai.

## Boundaries and review before official use

- This is a procurement document system, not stock valuation or financial accounting. Quantities/rates are editable when creating the next stage; cumulative partial delivery/receipt reconciliation and three-way matching are not implemented. Review quantities manually.
- Source order follows your requested sequence. In this version DO means a delivery record after PO. Confirm if TELEC's DO instead means an outward customer sales delivery order.
- TCSC process still needs your definition.
- Attachments, scanned signatures, vendor portals, WhatsApp/email sending, bank integration, e-invoicing and automatic backups are not included.
- Forms use one configurable office address and text company heading. Confirm the registered addresses, logos, tax fields and official document formats before issuing official printouts.
- Document lists/CSV/JSON load up to 5,000 records. JSON export excludes audit events and auth accounts and is not a complete database backup. Use Supabase database backups for full recovery.
- Session persists in the current browser tab, with token refresh. Admin provisions accounts. Password can be changed in Settings.
- Live hosting/database connection has not been performed: your own Supabase/Vercel configuration is required.

## Verification

Nine automated model tests check totals, source/vendor requirements, invalid values, inspection/gate pass fields, edit restrictions, HTML escaping and CSV formula escaping. Run `npm test` if Node.js is installed.

Schema and database workflow tested with local PostgreSQL-compatible PGlite, including the complete chain, status permissions, RLS, inactive accounts, cross-company sources, gate pass issue/return and audit entries. This is not a live Supabase integration test.

Browser checks also passed for the complete procurement chain, invoice submission, gate pass issue/return, demo persistence and a 390px mobile viewport, with no browser script errors.
