-- One parent account manages a family; children never need email credentials.
create schema if not exists imagineos_private;
revoke all on schema imagineos_private from public, anon, authenticated;

create table public.parent_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.families (
  id uuid primary key default gen_random_uuid(),
  parent_user_id uuid not null unique references public.parent_profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.child_profiles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 40),
  created_at timestamptz not null default now()
);
create index child_profiles_family_id_idx on public.child_profiles(family_id);

alter table public.parent_profiles enable row level security;
alter table public.families enable row level security;
alter table public.child_profiles enable row level security;
revoke all on public.parent_profiles, public.families, public.child_profiles from anon, authenticated;
grant select on public.parent_profiles, public.families, public.child_profiles to authenticated;
grant insert (family_id, nickname), update (nickname), delete on public.child_profiles to authenticated;

create policy parent_reads_self on public.parent_profiles for select to authenticated
  using (id = (select auth.uid()));
create policy parent_reads_family on public.families for select to authenticated
  using (parent_user_id = (select auth.uid()));
create policy parent_reads_children on public.child_profiles for select to authenticated
  using (exists (select 1 from public.families f where f.id = family_id and f.parent_user_id = (select auth.uid())));
create policy parent_adds_children on public.child_profiles for insert to authenticated
  with check (exists (select 1 from public.families f where f.id = family_id and f.parent_user_id = (select auth.uid())));
create policy parent_updates_children on public.child_profiles for update to authenticated
  using (exists (select 1 from public.families f where f.id = family_id and f.parent_user_id = (select auth.uid())))
  with check (exists (select 1 from public.families f where f.id = family_id and f.parent_user_id = (select auth.uid())));
create policy parent_deletes_children on public.child_profiles for delete to authenticated
  using (exists (select 1 from public.families f where f.id = family_id and f.parent_user_id = (select auth.uid())));

-- Privileged only because Auth's insert trigger must provision immutable ownership.
-- Not an RPC: private schema, empty search_path, no client EXECUTE privileges.
create function imagineos_private.provision_parent_family() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is not null and not coalesce(new.is_anonymous, false) then
    insert into public.parent_profiles(id) values (new.id);
    insert into public.families(parent_user_id) values (new.id);
  end if;
  return new;
end;
$$;
revoke all on function imagineos_private.provision_parent_family() from public, anon, authenticated;
create trigger imagineos_provision_parent after insert on auth.users
  for each row execute function imagineos_private.provision_parent_family();
