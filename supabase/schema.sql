-- Run once in a NEW Supabase project's SQL Editor. Back up an existing project before applying.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null, email text not null,
 role text not null default 'user' check(role in ('admin','approver','user')),
 active boolean not null default false
);
create function public.register_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,name,email) values(new.id,coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1)),new.email);return new;end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.register_profile();
insert into public.profiles(id,name,email) select id,coalesce(raw_user_meta_data->>'name',split_part(email,'@',1)),email from auth.users on conflict do nothing;
create function public.current_role() returns text language sql stable security definer set search_path=public as $$select role from public.profiles where id=auth.uid() and active=true$$;
create sequence public.document_number_seq;
create table public.documents (
 id uuid primary key default gen_random_uuid(),
 number text not null unique,
 type text not null check(type in ('IR','PR','QUOTATION','PO','DO','GRN','INSPECTION','INVOICE','TCSC','GATE_PASS')),
 company text not null check(company in ('TELEC Electronics & Machinery (Pvt.) Ltd.','TELEC Group','Trade Linker')),
 title text not null, date date not null default current_date, department text not null,
 party text not null default '', reference text not null default '',
 parent_id uuid references public.documents(id), items jsonb not null, tax numeric not null default 0 check(tax between 0 and 100),
 notes text not null default '',extra jsonb not null default '{}'::jsonb,
 status text not null default 'Draft' check(status in ('Draft','Pending','Approved','Rejected','Submitted','Issued','Returned')),
 created_by uuid not null default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index documents_parent_idx on public.documents(parent_id);
create index documents_type_status_idx on public.documents(type,status);
create table public.document_events (
 id uuid primary key default gen_random_uuid(),document_id uuid not null references public.documents(id),
 actor text not null,action text not null,note text not null default '',created_at timestamptz not null default now()
);
create index events_document_idx on public.document_events(document_id);
create function public.validate_document() returns trigger language plpgsql security definer set search_path=public as $$
declare r text:=public.current_role(); p public.documents; expected text; item jsonb;
begin
 if r is null then raise exception 'Active account required';end if;
 if TG_OP='INSERT' then
  if new.created_by<>auth.uid() or new.status<>'Draft' then raise exception 'Create your own draft only';end if;
  new.id:=gen_random_uuid();new.number:=new.type||'-'||extract(year from now() at time zone 'Asia/Karachi')::text||'-'||lpad(nextval('public.document_number_seq')::text,6,'0');new.created_at:=now();
 else
  if new.id<>old.id or new.number<>old.number or new.type<>old.type or new.created_by<>old.created_by or new.created_at<>old.created_at then raise exception 'Document identity is immutable';end if;
  -- Status transitions are exclusively handled by the locked RPC. Direct PATCH cannot change status.
  if new.status<>old.status then
   if current_setting('telec.transition',true) is distinct from 'allowed' then raise exception 'Use the transition function';end if;
  elsif old.status not in ('Draft','Rejected') then raise exception 'Only drafts and rejected documents can be edited';
  elsif old.created_by<>auth.uid() and r<>'admin' then raise exception 'Only the owner or administrator may edit';end if;
 end if;
 if length(trim(new.title))=0 or length(trim(new.department))=0 then raise exception 'Title and department required';end if;
 if jsonb_typeof(new.items)<>'array' then raise exception 'Items must be an array';end if;
 if jsonb_array_length(new.items)=0 then raise exception 'At least one item required';end if;
 for item in select value from jsonb_array_elements(new.items) loop
  if coalesce(length(trim(item->>'description')),0)=0 or jsonb_typeof(item->'qty') is distinct from 'number' or jsonb_typeof(item->'rate') is distinct from 'number' then raise exception 'Invalid item description or numbers';end if;
  if (item->>'qty')::numeric<=0 or (item->>'rate')::numeric<0 then raise exception 'Invalid quantity or rate';end if;
 end loop;
 if jsonb_typeof(new.extra)<>'object' then raise exception 'Extra fields must be an object';end if;
 if new.type in ('QUOTATION','PO','INVOICE') and length(trim(new.party))=0 then raise exception 'Vendor / party required';end if;
 expected:=case new.type when 'PR' then 'IR' when 'QUOTATION' then 'PR' when 'PO' then 'QUOTATION' when 'DO' then 'PO' when 'GRN' then 'DO' when 'INSPECTION' then 'GRN' when 'INVOICE' then 'INSPECTION' end;
 if expected is not null then
  if new.parent_id is null then raise exception 'Approved source required';end if;
  select * into p from public.documents where id=new.parent_id for share;
  if not found or p.type<>expected or p.status<>'Approved' or p.company<>new.company then raise exception 'Approved source of correct type in same company required';end if;
  if p.type='INSPECTION' and p.extra->>'result'='Rejected' then raise exception 'Rejected inspection cannot be invoiced';end if;
 elsif new.parent_id is not null then raise exception 'This module has no source document';end if;
 if new.type='INSPECTION' and coalesce(new.extra->>'result','') not in ('Accepted','Rejected','Partially accepted') then raise exception 'Inspection result required';end if;
 if new.type='GATE_PASS' then
  if coalesce(new.extra->>'pass_type','') not in ('Returnable','Non-returnable') then raise exception 'Gate pass type required';end if;
  if new.extra->>'pass_type'='Returnable' then
   if coalesce(new.extra->>'expected_return','')='' then raise exception 'Expected return date required';end if;
   if (new.extra->>'expected_return')::date<new.date then raise exception 'Return date precedes pass date';end if;
  end if;
 end if;
 new.updated_at:=now();return new;
end $$;
create trigger validate_document_before_write before insert or update on public.documents for each row execute function public.validate_document();
create function public.log_document_write() returns trigger language plpgsql security definer set search_path=public as $$
declare actor_name text;
begin
 select name into actor_name from public.profiles where id=auth.uid();
 insert into public.document_events(document_id,actor,action,note) values(new.id,coalesce(actor_name,'Unknown'),case when TG_OP='INSERT' then 'Created' when new.status<>old.status then new.status else 'Edited' end,case when TG_OP='UPDATE' and new.status<>old.status then coalesce(current_setting('telec.transition_note',true),'') else '' end);return new;
end $$;
create trigger log_document_after_write after insert or update on public.documents for each row execute function public.log_document_write();
create function public.transition_document(p_id uuid,p_status text,p_note text default '') returns void language plpgsql security definer set search_path=public as $$
declare d public.documents;r text:=public.current_role();
begin
 if r is null then raise exception 'Active account required';end if;
 select * into d from public.documents where id=p_id for update;
 if not found then raise exception 'Document not found';end if;
 if d.status in ('Draft','Rejected') and p_status='Pending' then
  if d.created_by<>auth.uid() and r<>'admin' then raise exception 'Owner or administrator required';end if;
 elsif d.status='Pending' and p_status in ('Approved','Rejected') then
  if r not in ('admin','approver') then raise exception 'Approver role required';end if;
  if d.created_by=auth.uid() then raise exception 'Another approver must review your document';end if;
 elsif d.type='INVOICE' and d.status='Approved' and p_status='Submitted' then
  if d.created_by<>auth.uid() and r not in ('admin','approver') then raise exception 'Owner or approver required';end if;
 elsif d.type='GATE_PASS' and d.status='Approved' and p_status='Issued' then
  if r not in ('admin','approver') then raise exception 'Approver role required';end if;
 elsif d.type='GATE_PASS' and d.status='Issued' and p_status='Returned' and d.extra->>'pass_type'='Returnable' then
  if r not in ('admin','approver') then raise exception 'Approver role required';end if;
 else raise exception 'Invalid status transition';end if;
 if p_status in ('Rejected','Submitted','Issued','Returned') and coalesce(length(trim(p_note)),0)=0 then raise exception 'A note is required';end if;
 perform set_config('telec.transition','allowed',true);perform set_config('telec.transition_note',coalesce(p_note,''),true);
 update public.documents set status=p_status where id=p_id;
 perform set_config('telec.transition','',true);perform set_config('telec.transition_note','',true);
end $$;
create function public.set_user_access(p_user uuid,p_role text,p_active boolean) returns void language plpgsql security definer set search_path=public as $$
begin
 if public.current_role() is distinct from 'admin' then raise exception 'Administrator required';end if;
 if p_user=auth.uid() then raise exception 'Cannot change own access';end if;
 if p_role not in ('admin','approver','user') then raise exception 'Invalid role';end if;
 update public.profiles set role=p_role,active=p_active where id=p_user;
 if not found then raise exception 'User not found';end if;
end $$;
alter table public.profiles enable row level security;
alter table public.documents enable row level security;
alter table public.document_events enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.current_role()='admin');
create policy document_read on public.documents for select to authenticated using(public.current_role() is not null);
create policy document_insert on public.documents for insert to authenticated with check(public.current_role() is not null and created_by=auth.uid() and status='Draft');
create policy document_edit on public.documents for update to authenticated using(public.current_role() is not null and status in ('Draft','Rejected') and (created_by=auth.uid() or public.current_role()='admin')) with check(public.current_role() is not null and status in ('Draft','Rejected') and (created_by=auth.uid() or public.current_role()='admin'));
create policy event_read on public.document_events for select to authenticated using(public.current_role() is not null);
revoke all on public.profiles,public.documents,public.document_events from anon,authenticated;
grant select on public.profiles,public.document_events to authenticated;
grant select,insert,update on public.documents to authenticated;
-- Every SECURITY DEFINER function is private except explicitly permitted RPC/helper functions.
revoke all on function public.register_profile(),public.validate_document(),public.log_document_write(),public.current_role(),public.transition_document(uuid,text,text),public.set_user_access(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.current_role(),public.transition_document(uuid,text,text),public.set_user_access(uuid,text,boolean) to authenticated;
commit;
