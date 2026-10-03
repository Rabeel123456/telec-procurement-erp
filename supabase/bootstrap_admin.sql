-- 1. Create your account in Supabase Authentication > Users > Add user.
-- 2. Replace the email below with that exact account email, then run this in SQL Editor.
update public.profiles set role='admin',active=true where email='YOUR_EMAIL_HERE';
-- Create a SECOND account and activate it as approver in the ERP.
-- A document creator cannot approve their own document.
