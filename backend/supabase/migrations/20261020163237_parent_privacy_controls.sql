-- Parent access is a short-lived, session-bound capability, never a client flag.
create table imagineos_private.parent_access (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  token_hash text not null check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null
);
create index parent_access_family_idx on imagineos_private.parent_access(family_id);
create table imagineos_private.parent_access_limits (
  family_id uuid primary key references public.families(id) on delete cascade,
  window_start timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0)
);
create table imagineos_private.family_deletions (
  family_id uuid primary key references public.families(id) on delete cascade,
  requested_at timestamptz not null default now()
);
alter table imagineos_private.parent_access enable row level security;
alter table imagineos_private.parent_access_limits enable row level security;
alter table imagineos_private.family_deletions enable row level security;
revoke all on imagineos_private.parent_access, imagineos_private.parent_access_limits,
  imagineos_private.family_deletions from public, anon, authenticated;

-- Serialize writes against the irreversible deletion request. Auth deletion's
-- cascading referential cleanup is allowed after the Auth row has disappeared.
create function imagineos_private.guard_family_write() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_parent uuid;
begin
  select parent_user_id into v_parent from public.families where id=new.family_id for update;
  if exists(select 1 from imagineos_private.family_deletions where family_id=new.family_id)
    and exists(select 1 from auth.users where id=v_parent) then
    raise exception 'Finish deleting this family account';
  end if;
  return new;
end; $$;
revoke all on function imagineos_private.guard_family_write() from public,anon,authenticated;
create trigger family_write_guard before insert or update on public.child_profiles
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.characters
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.character_versions
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.original_assets
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.story_page_drafts
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.story_projects
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on public.story_panels
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert or update on imagineos_private.provider_connections
  for each row execute function imagineos_private.guard_family_write();
create trigger family_write_guard before insert on imagineos_private.illustration_jobs
  for each row execute function imagineos_private.guard_family_write();

-- Storage inserts also hold the family lock, including uploads reserved before
-- deletion began. Files are erased through the Storage API, never SQL DELETE.
create or replace function imagineos_upload_private.pending_original(p_path text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_status text;
begin
  if auth.uid() is null or not exists(select 1 from auth.sessions
    where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid()) then return false; end if;
  select id into v_family from public.families where parent_user_id=auth.uid() for update;
  if v_family is null or exists(select 1 from imagineos_private.family_deletions
    where family_id=v_family) then return false; end if;
  select state into v_status from public.original_assets
    where object_path=p_path and family_id=v_family for update;
  return coalesce(v_status='pending',false);
end; $$;

create function imagineos_private.parent_controls(
  p_parent_id uuid, p_session_id uuid, p_action text, p_token_hash text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_attempts integer; v_expires timestamptz; v_paths jsonb;
begin
  if not exists(select 1 from auth.sessions where id=p_session_id and user_id=p_parent_id)
    then raise insufficient_privilege; end if;
  select id into v_family from public.families where parent_user_id=p_parent_id for update;
  if v_family is null then raise insufficient_privilege; end if;
  if p_action='attempt' then
    insert into imagineos_private.parent_access_limits(family_id,attempts) values(v_family,1)
    on conflict(family_id) do update set
      attempts=case when parent_access_limits.window_start < now()-interval '1 hour'
        then 1 else parent_access_limits.attempts+1 end,
      window_start=case when parent_access_limits.window_start < now()-interval '1 hour'
        then now() else parent_access_limits.window_start end returning attempts into v_attempts;
    return to_jsonb(v_attempts<=10);
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then raise insufficient_privilege; end if;
  if p_action='unlock' then
    v_expires:=now()+interval '5 minutes';
    insert into imagineos_private.parent_access(session_id,family_id,token_hash,expires_at)
      values(p_session_id,v_family,p_token_hash,v_expires)
    on conflict(session_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at;
    return jsonb_build_object('expires_at',v_expires);
  end if;
  if p_action='lock' then
    delete from imagineos_private.parent_access where session_id=p_session_id and token_hash=p_token_hash;
    return 'true'::jsonb;
  end if;
  if not exists(select 1 from imagineos_private.parent_access where session_id=p_session_id
    and family_id=v_family and token_hash=p_token_hash and expires_at>now()) then return null; end if;
  if p_action='overview' then
    return jsonb_build_object(
      'child_profiles',(select count(*) from public.child_profiles where family_id=v_family),
      'characters',(select count(*) from public.characters where family_id=v_family),
      'versions',(select count(*) from public.character_versions where family_id=v_family),
      'original_files',(select count(*) from storage.objects where bucket_id='character-originals'
        and name like v_family::text||'/%'),
      'page_drafts',(select count(*) from public.story_page_drafts where family_id=v_family),
      'stories',(select count(*) from public.story_projects where family_id=v_family and not deleted),
      'provider_connections',(select count(*) from imagineos_private.provider_connections where family_id=v_family),
      'deletion_pending',exists(select 1 from imagineos_private.family_deletions where family_id=v_family),
      'generation_enabled',false);
  end if;
  if p_action='delete_begin' then
    -- A future live adapter must settle uncertain charges before this workflow.
    if exists(select 1 from imagineos_private.illustration_jobs where family_id=v_family
      and state in ('reserved','running','indeterminate')) then raise exception 'Illustration settlement required'; end if;
    insert into imagineos_private.family_deletions(family_id) values(v_family) on conflict do nothing;
    -- Revoking connections immediately prevents any later provider claim.
    delete from imagineos_private.provider_connections where family_id=v_family;
    return 'true'::jsonb;
  end if;
  if p_action in ('delete_batch','delete_ready') then
    if not exists(select 1 from imagineos_private.family_deletions where family_id=v_family)
      then raise insufficient_privilege; end if;
    if p_action='delete_ready' then
      return to_jsonb(not exists(select 1 from storage.objects where
        (bucket_id='character-originals' and name like v_family::text||'/%')
        or owner_id=p_parent_id::text));
    end if;
    select coalesce(jsonb_agg(name),'[]'::jsonb) into v_paths from
      (select name from storage.objects where bucket_id='character-originals'
        and name like v_family::text||'/%' order by name limit 100) batch;
    return v_paths;
  end if;
  raise exception 'Invalid parent action';
end; $$;
revoke all on function imagineos_private.parent_controls(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function imagineos_private.parent_controls(uuid,uuid,text,text) to service_role;
create function public.parent_controls(
  p_parent_id uuid,p_session_id uuid,p_action text,p_token_hash text default null
) returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_private.parent_controls(p_parent_id,p_session_id,p_action,p_token_hash);
$$;
revoke all on function public.parent_controls(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.parent_controls(uuid,uuid,text,text) to service_role;
