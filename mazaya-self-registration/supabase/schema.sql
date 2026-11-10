-- Mazaya membership registration schema
create extension if not exists pgcrypto;

create table if not exists public.associations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null,
  registration_number text not null unique,
  founded_year integer,
  region text not null default 'منطقة الرياض' check (region = 'منطقة الرياض'),
  city text not null,
  address text,
  website text,
  contact_name text not null,
  contact_title text,
  contact_phone text not null,
  contact_email text not null,
  account_status text not null default 'active' check (account_status in ('active','suspended')),
  membership_status text not null default 'pending' check (membership_status in ('pending','approved','rejected','needs_info')),
  membership_category text check (membership_category in ('A','B','منتسبة','غير منتسبة')),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.council_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_council_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.council_admins where user_id = auth.uid()); $$;

alter table public.associations enable row level security;
alter table public.council_admins enable row level security;

-- A signed-in account can create one association profile only.
create policy "association owner can insert own profile" on public.associations
for insert to authenticated with check (owner_id = auth.uid());
create policy "owner can view own association" on public.associations
for select to authenticated using (owner_id = auth.uid() or public.is_council_admin());
-- Owners may edit contact/profile fields only. Membership status/category are
-- changed exclusively through the council-only functions below.
revoke update on public.associations from authenticated;
grant update (name, founded_year, city, address, website, contact_name, contact_title, contact_phone, contact_email, updated_at)
on public.associations to authenticated;
create policy "owner can update own basic profile" on public.associations
for update to authenticated using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create or replace function public.force_pending_on_registration()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.owner_id <> auth.uid() then raise exception 'Invalid owner'; end if;
  new.account_status := 'active';
  new.membership_status := 'pending';
  new.membership_category := null;
  new.reviewed_at := null;
  return new;
end;
$$;
drop trigger if exists associations_force_pending on public.associations;
create trigger associations_force_pending before insert on public.associations
for each row execute function public.force_pending_on_registration();

create or replace function public.council_set_membership(p_association_id uuid, p_category text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_council_admin() then raise exception 'Not authorized'; end if;
  if p_category not in ('A','B','منتسبة','غير منتسبة') then raise exception 'Invalid category'; end if;
  update public.associations set membership_status='approved', membership_category=p_category,
    reviewed_at=now(), updated_at=now() where id=p_association_id;
  if not found then raise exception 'Association not found'; end if;
end;
$$;

create or replace function public.council_reject_membership(p_association_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_council_admin() then raise exception 'Not authorized'; end if;
  update public.associations set membership_status='rejected', membership_category=null,
    reviewed_at=now(), updated_at=now() where id=p_association_id;
  if not found then raise exception 'Association not found'; end if;
end;
$$;
revoke all on function public.council_set_membership(uuid,text) from public;
revoke all on function public.council_reject_membership(uuid) from public;
grant execute on function public.council_set_membership(uuid,text) to authenticated;
grant execute on function public.council_reject_membership(uuid) to authenticated;
create policy "admins can view admin list" on public.council_admins
for select to authenticated using (user_id = auth.uid() or public.is_council_admin());

-- IMPORTANT: Create the first council admin only after that person has registered
-- through Supabase Auth. Replace AUTH_USER_UUID with their auth.users UUID.
-- insert into public.council_admins(user_id) values ('AUTH_USER_UUID');

-- Recommended production hardening:
-- 1) Move admin approval to a server-side RPC with explicit audit logging.
-- 2) Add an association_audit table and immutable audit triggers.
-- 3) Add rate limiting / CAPTCHA to public registration.
-- 4) Validate registration numbers against the official source if an API is available.
