create schema imagineos_child_private;
revoke all on schema imagineos_child_private from public,anon,authenticated;
grant usage on schema imagineos_child_private to service_role;
create table imagineos_child_private.settings (
  child_id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  duration_minutes integer not null default 30 check(duration_minutes between 1 and 480),
  allow_export boolean not null default false,
  blocked boolean not null default false,
  foreign key(child_id,family_id) references public.child_profiles(id,family_id) on delete cascade,
  unique(child_id,family_id)
);
create index child_settings_family_idx on imagineos_child_private.settings(family_id);
insert into imagineos_child_private.settings(child_id,family_id) select id,family_id from public.child_profiles;
create table imagineos_child_private.approvals (
  code_hash text primary key check(code_hash ~ '^[a-f0-9]{64}$'),
  child_id uuid not null,
  family_id uuid not null,
  minutes integer not null check(minutes between 1 and 480),
  created_at timestamptz not null default clock_timestamp(),
  redeem_before timestamptz not null default clock_timestamp()+interval '10 minutes',
  foreign key(child_id,family_id) references imagineos_child_private.settings(child_id,family_id) on delete cascade
);
create index child_approvals_family_idx on imagineos_child_private.approvals(family_id);
create index child_approvals_child_family_idx on imagineos_child_private.approvals(child_id,family_id);
create table imagineos_child_private.sessions (
  id uuid primary key,
  token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
  approval_hash text not null unique references imagineos_child_private.approvals(code_hash) on delete cascade,
  child_id uuid not null,
  family_id uuid not null,
  expires_at timestamptz not null,
  ended_at timestamptz,
  foreign key(child_id,family_id) references imagineos_child_private.settings(child_id,family_id) on delete cascade
);
create index child_sessions_family_idx on imagineos_child_private.sessions(family_id);
create index child_sessions_child_family_idx on imagineos_child_private.sessions(child_id,family_id);
create table imagineos_child_private.approval_limits (
  family_id uuid primary key references public.families(id) on delete cascade,
  window_start timestamptz not null default clock_timestamp(),
  attempts integer not null default 0
);
alter table imagineos_child_private.settings enable row level security;
alter table imagineos_child_private.approvals enable row level security;
alter table imagineos_child_private.sessions enable row level security;
alter table imagineos_child_private.approval_limits enable row level security;
revoke all on all tables in schema imagineos_child_private from public,anon,authenticated;

create function imagineos_child_private.provision_settings() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into imagineos_child_private.settings(child_id,family_id) values(new.id,new.family_id);
  return new;
end; $$;
revoke all on function imagineos_child_private.provision_settings() from public,anon,authenticated;
create trigger child_access_settings after insert on public.child_profiles
  for each row execute function imagineos_child_private.provision_settings();

create function imagineos_child_private.current_session()
returns imagineos_child_private.sessions language plpgsql security definer set search_path='' as $$
declare v_session imagineos_child_private.sessions;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise insufficient_privilege; end if;
  select s.* into v_session from imagineos_child_private.sessions s
    join imagineos_child_private.settings c on c.child_id=s.child_id and c.family_id=s.family_id
    where s.token_hash=current_setting('imagineos.child_token_hash',true)
    and s.ended_at is null and s.expires_at>clock_timestamp() and not c.blocked
    and not exists(select 1 from imagineos_private.family_deletions d where d.family_id=s.family_id);
  if not found then raise insufficient_privilege; end if;
  return v_session;
end; $$;
revoke all on function imagineos_child_private.current_session() from public,anon,authenticated;

-- This helper is shared by the existing save algorithms. It never changes JWT
-- claims or impersonates the parent. Only the service-only child RPC sets context.
create function imagineos_child_private.creator_family(p_child uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_session imagineos_child_private.sessions;
begin
  if auth.uid() is not null then
    if not exists(select 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid
      and user_id=auth.uid()) then raise insufficient_privilege; end if;
    select id into v_family from public.families where parent_user_id=auth.uid() for update;
    if p_child is not null and not exists(select 1 from public.child_profiles
      where id=p_child and family_id=v_family) then raise insufficient_privilege; end if;
  else
    v_session:=imagineos_child_private.current_session();
    perform 1 from public.families where id=v_session.family_id for update;
    v_session:=imagineos_child_private.current_session();
    if p_child is not null and p_child<>v_session.child_id then raise insufficient_privilege; end if;
    v_family:=v_session.family_id;
  end if;
  if v_family is null or exists(select 1 from imagineos_private.family_deletions where family_id=v_family)
    then raise insufficient_privilege; end if;
  return v_family;
end; $$;
revoke all on function imagineos_child_private.creator_family(uuid) from public,anon,authenticated;

create function imagineos_child_private.asset_family(p_asset uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_child uuid;
begin
  select c.child_profile_id into v_child from public.original_assets a
    join public.character_versions v on v.id=a.version_id join public.characters c on c.id=v.character_id
    where a.id=p_asset;
  if v_child is null then raise insufficient_privilege; end if;
  return imagineos_child_private.creator_family(v_child);
end; $$;
revoke all on function imagineos_child_private.asset_family(uuid) from public,anon,authenticated;

create function imagineos_child_private.session_info(p_session imagineos_child_private.sessions)
returns jsonb language sql security invoker set search_path='' as $$
  select jsonb_build_object('child_id',c.id,'nickname',c.nickname,'session_id',(p_session).id,
    'expires_at',(p_session).expires_at,'server_time',clock_timestamp(),'allow_export',s.allow_export,'ai_enabled',false)
  from public.child_profiles c join imagineos_child_private.settings s on s.child_id=c.id
  where c.id=(p_session).child_id and c.family_id=(p_session).family_id;
$$;
revoke all on function imagineos_child_private.session_info(imagineos_child_private.sessions) from public,anon,authenticated;

create function imagineos_child_private.manage(
  p_parent uuid,p_session uuid,p_grant_hash text,p_action text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_child uuid; v_minutes integer; v_attempts integer;
begin
  if not exists(select 1 from auth.sessions where id=p_session and user_id=p_parent) then raise insufficient_privilege; end if;
  select id into v_family from public.families where parent_user_id=p_parent for update;
  if v_family is null or not exists(select 1 from imagineos_private.parent_access where session_id=p_session
    and family_id=v_family and token_hash=p_grant_hash and expires_at>clock_timestamp())
    or exists(select 1 from imagineos_private.family_deletions where family_id=v_family) then raise insufficient_privilege; end if;
  if p_action='child_list' then
    return jsonb_build_object('profiles',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'nickname',c.nickname,
      'minutes',s.duration_minutes,'allow_export',s.allow_export,'blocked',s.blocked) order by c.created_at)
      from public.child_profiles c join imagineos_child_private.settings s on s.child_id=c.id
      where c.family_id=v_family),'[]'::jsonb),'sessions',coalesce((select jsonb_agg(jsonb_build_object(
        'id',s.id,'child_id',s.child_id,'nickname',c.nickname,'expires_at',s.expires_at) order by s.expires_at)
        from imagineos_child_private.sessions s join public.child_profiles c on c.id=s.child_id
        where s.family_id=v_family and s.ended_at is null and s.expires_at>clock_timestamp()),'[]'::jsonb));
  elsif p_action='child_add' then
    if jsonb_typeof(p_data->'nickname')<>'string' or char_length(btrim(p_data->>'nickname')) not between 1 and 40
      then raise exception 'Invalid nickname'; end if;
    insert into public.child_profiles(family_id,nickname) values(v_family,btrim(p_data->>'nickname')) returning id into v_child;
    return jsonb_build_object('child_id',v_child);
  elsif p_action='child_end' then
    update imagineos_child_private.sessions set ended_at=clock_timestamp()
      where id=(p_data->>'session_id')::uuid and family_id=v_family;
    return jsonb_build_object('updated',true);
  end if;
  v_child:=(p_data->>'child_id')::uuid;
  if not exists(select 1 from imagineos_child_private.settings where child_id=v_child and family_id=v_family)
    then raise insufficient_privilege; end if;
  if p_action='child_settings' then
    v_minutes:=(p_data->>'minutes')::integer;
    if v_minutes not between 1 and 480 or jsonb_typeof(p_data->'allow_export')<>'boolean'
      or jsonb_typeof(p_data->'blocked')<>'boolean' then raise exception 'Invalid settings'; end if;
    update imagineos_child_private.settings set duration_minutes=v_minutes,
      allow_export=(p_data->>'allow_export')::boolean,blocked=(p_data->>'blocked')::boolean where child_id=v_child;
    if (p_data->>'blocked')::boolean then
      update imagineos_child_private.sessions set ended_at=clock_timestamp() where child_id=v_child and ended_at is null;
      update imagineos_child_private.approvals set redeem_before=clock_timestamp() where child_id=v_child;
    end if;
    return jsonb_build_object('updated',true);
  elsif p_action='child_approve' then
    v_minutes:=(p_data->>'minutes')::integer;
    if v_minutes is null or v_minutes not between 1 and 480 or p_data->>'code_hash' is null
      or p_data->>'code_hash' !~ '^[0-9a-f]{64}$' then raise exception 'Invalid approval'; end if;
    if exists(select 1 from imagineos_child_private.settings where child_id=v_child and blocked) then raise insufficient_privilege; end if;
    insert into imagineos_child_private.approval_limits(family_id,attempts) values(v_family,1)
      on conflict(family_id) do update set attempts=case when approval_limits.window_start<clock_timestamp()-interval '1 hour'
        then 1 else approval_limits.attempts+1 end,window_start=case when approval_limits.window_start<clock_timestamp()-interval '1 hour'
        then clock_timestamp() else approval_limits.window_start end returning attempts into v_attempts;
    if v_attempts>60 then return null; end if;
    -- Bounded cleanup of expired capability metadata; no creative work is erased.
    delete from imagineos_child_private.approvals a where family_id=v_family and redeem_before<clock_timestamp()-interval '1 day'
      and not exists(select 1 from imagineos_child_private.sessions s where s.approval_hash=a.code_hash and s.ended_at is null and s.expires_at>clock_timestamp());
    insert into imagineos_child_private.approvals(code_hash,child_id,family_id,minutes)
      values(p_data->>'code_hash',v_child,v_family,v_minutes);
    return jsonb_build_object('redeem_before',clock_timestamp()+interval '10 minutes','minutes',v_minutes);
  end if;
  raise exception 'Unknown child management action';
end; $$;
revoke all on function imagineos_child_private.manage(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function imagineos_child_private.manage(uuid,uuid,text,text,jsonb) to service_role;
create function public.manage_child_access(p_parent uuid,p_session uuid,p_grant_hash text,p_action text,p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_child_private.manage(p_parent,p_session,p_grant_hash,p_action,p_data);
$$;
revoke all on function public.manage_child_access(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.manage_child_access(uuid,uuid,text,text,jsonb) to service_role;

create function imagineos_child_private.access(
  p_action text,p_token_hash text,p_data jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session imagineos_child_private.sessions; v_approval imagineos_child_private.approvals;
  v_family uuid; v_asset uuid; v_result jsonb; v_offset integer;
begin
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then raise insufficient_privilege; end if;
  perform set_config('imagineos.child_token_hash',p_token_hash,true);
  if p_action='login' then
    select family_id into v_family from imagineos_child_private.approvals where code_hash=p_data->>'code_hash';
    if v_family is null then raise insufficient_privilege; end if;
    perform 1 from public.families where id=v_family for update;
    select * into v_approval from imagineos_child_private.approvals where code_hash=p_data->>'code_hash' for update;
    select * into v_session from imagineos_child_private.sessions where approval_hash=v_approval.code_hash;
    if found then
      if v_session.id<>(p_data->>'request_id')::uuid or v_session.token_hash<>p_token_hash then raise insufficient_privilege; end if;
      return imagineos_child_private.session_info(imagineos_child_private.current_session());
    end if;
    if v_approval.redeem_before<=clock_timestamp() or exists(select 1 from imagineos_child_private.settings
      where child_id=v_approval.child_id and blocked) or exists(select 1 from imagineos_private.family_deletions
      where family_id=v_family) then raise insufficient_privilege; end if;
    insert into imagineos_child_private.sessions(id,token_hash,approval_hash,child_id,family_id,expires_at)
      values((p_data->>'request_id')::uuid,p_token_hash,v_approval.code_hash,v_approval.child_id,v_family,
        clock_timestamp()+make_interval(mins=>v_approval.minutes)) returning * into v_session;
    return imagineos_child_private.session_info(v_session);
  end if;
  v_session:=imagineos_child_private.current_session();
  if p_action='status' then return imagineos_child_private.session_info(v_session); end if;
  if p_action='logout' then
    update imagineos_child_private.sessions set ended_at=clock_timestamp() where id=v_session.id;
    return 'true'::jsonb;
  end if;
  if p_action='authorize_export' then
    if not exists(select 1 from imagineos_child_private.settings where child_id=v_session.child_id and allow_export)
      then raise insufficient_privilege; end if;
    return 'true'::jsonb;
  elsif p_action='library' then
    return jsonb_build_object('creators',(select jsonb_build_array(jsonb_build_object('id',id,'nickname',nickname))
      from public.child_profiles where id=v_session.child_id and family_id=v_session.family_id),
      'versions',coalesce((select jsonb_agg(to_jsonb(v) order by version_number desc) from public.original_uploads v
        where v.family_id=v_session.family_id and v.child_profile_id=v_session.child_id
        and v.state in ('pending','ready') and not v.deleting_character),'[]'::jsonb));
  elsif p_action='stories' then
    v_offset:=(p_data->>'offset')::integer;
    if v_offset is null or v_offset not between 0 and 1000000 then raise exception 'Invalid offset'; end if;
    select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into v_result from
      (select v.* from public.story_project_snapshots v join public.story_projects p on p.id=v.id
        where p.family_id=v_session.family_id and p.child_id=v_session.child_id and not p.deleted
        order by v.updated_at desc,v.id offset v_offset limit 20) s;
    return v_result;
  elsif p_action='save_story' then
    if (p_data->>'child_id')::uuid is distinct from v_session.child_id then raise insufficient_privilege; end if;
    return to_jsonb(imagineos_story_private.save_story_project((p_data->>'id')::uuid,v_session.child_id,
      (p_data->>'revision')::integer,p_data->>'title',p_data->>'format',p_data->'panels'));
  elsif p_action='reserve' then
    if (p_data->>'child_id')::uuid is distinct from v_session.child_id then raise insufficient_privilege; end if;
    return imagineos_upload_private.reserve_original((p_data->>'request_id')::uuid,v_session.child_id,
      (p_data->>'character_id')::uuid,p_data->>'name',p_data->>'mime_type',(p_data->>'byte_size')::integer,p_data->>'sha256');
  end if;
  v_asset:=(p_data->>'asset_id')::uuid;
  if not exists(select 1 from public.original_assets a join public.character_versions v on v.id=a.version_id
    join public.characters c on c.id=v.character_id where a.id=v_asset and a.family_id=v_session.family_id
    and c.child_profile_id=v_session.child_id and a.state in ('pending','ready')
    and not c.deletion_requested and not v.deletion_requested) then raise insufficient_privilege; end if;
  if p_action='asset' then
    select jsonb_build_object('path',object_path,'mime_type',mime_type,'sha256',sha256,'byte_size',byte_size,'state',state)
      into v_result from public.original_assets where id=v_asset;
    return v_result;
  elsif p_action='finish' then
    perform imagineos_upload_private.finish_original(v_asset);
    return 'true'::jsonb;
  elsif p_action='cancel' then
    perform imagineos_upload_private.cancel_original(v_asset);
    return 'true'::jsonb;
  elsif p_action='pages' then
    select coalesce(jsonb_agg(to_jsonb(p) order by updated_at desc),'[]'::jsonb) into v_result
      from public.saved_story_drafts p where source_id=v_asset and family_id=v_session.family_id;
    return v_result;
  elsif p_action='save_page' then
    return to_jsonb(imagineos_story_private.save_story_draft((p_data->>'page_id')::uuid,v_asset,
      (p_data->>'revision')::integer,p_data->>'scene',p_data->>'dialogue',p_data->>'narration'));
  end if;
  raise exception 'Unknown child action';
end; $$;
revoke all on function imagineos_child_private.access(text,text,jsonb) from public,anon,authenticated;
grant execute on function imagineos_child_private.access(text,text,jsonb) to service_role;
create function public.child_access(p_action text,p_token_hash text,p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_child_private.access(p_action,p_token_hash,p_data);
$$;
revoke all on function public.child_access(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.child_access(text,text,jsonb) to service_role;

-- Reuse the established save/revision algorithms with explicit creator scope.
create or replace function imagineos_upload_private.reserve_original(
  p_request_id uuid, p_child_id uuid, p_character_id uuid, p_name text,
  p_mime_type text, p_byte_size integer, p_sha256 text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare family uuid; character uuid; version uuid; number integer; existing public.original_uploads%rowtype;
begin
  family:=imagineos_child_private.creator_family(p_child_id);
  if p_request_id is null or p_name is null or char_length(btrim(p_name)) not between 1 and 80
    or p_mime_type is null or p_mime_type not in ('image/png','image/jpeg','image/webp')
    or p_byte_size is null or p_byte_size not between 1 and 5242880
    or p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid original upload' using errcode='22023';
  end if;
  -- Serialize equal retry keys, including conflicting requests from other families.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
  select * into existing from public.original_uploads where request_id=p_request_id;
  if found then
    if existing.family_id<>family or existing.child_profile_id<>p_child_id
      or (p_character_id is not null and existing.character_id<>p_character_id)
      or existing.name<>btrim(p_name) or existing.mime_type<>p_mime_type
      or existing.byte_size<>p_byte_size or existing.sha256<>p_sha256
      or existing.state='cancelled' then
      raise exception 'Upload retry does not match the reserved original' using errcode='22023';
    end if;
    return to_jsonb(existing);
  end if;
  if p_character_id is null then
    insert into public.characters(family_id,child_profile_id) values (family,p_child_id) returning id into character;
  else
    select id into character from public.characters where id=p_character_id and family_id=family
      and child_profile_id=p_child_id for update;
    if character is null then raise insufficient_privilege; end if;
  end if;
  select coalesce(max(version_number),0)+1 into number from public.character_versions where character_id=character;
  insert into public.character_versions(character_id,family_id,version_number,name)
    values (character,family,number,btrim(p_name)) returning id into version;
  insert into public.original_assets(id,version_id,family_id,object_path,mime_type,byte_size,sha256)
    values (p_request_id,version,family,family::text||'/'||p_request_id::text,p_mime_type,p_byte_size,p_sha256);
  select * into existing from public.original_uploads where request_id=p_request_id;
  return to_jsonb(existing);
end; $$;

create or replace function imagineos_upload_private.finish_original(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare asset public.original_assets%rowtype; metadata jsonb;
begin
  perform imagineos_child_private.asset_family(p_request_id);
  select * into asset from public.original_assets where id=p_request_id for update;
  if not found then raise insufficient_privilege; end if;
  if asset.state='ready' then return; end if;
  if asset.state<>'pending' then raise exception 'Upload was discarded'; end if;
  select o.metadata into metadata from storage.objects o
    where o.bucket_id='character-originals' and o.name=asset.object_path;
  if metadata is null or (metadata->>'size')::bigint is distinct from asset.byte_size::bigint
    or metadata->>'mimetype' is distinct from asset.mime_type then
    raise exception 'Original upload is incomplete or does not match its reservation';
  end if;
  update public.original_assets set state='ready' where id=asset.id;
end; $$;

create or replace function imagineos_upload_private.cancel_original(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare asset public.original_assets%rowtype;
begin
  perform imagineos_child_private.asset_family(p_request_id);
  select * into asset from public.original_assets where id=p_request_id for update;
  if not found then raise insufficient_privilege; end if;
  if asset.state='cancelled' then return; end if;
  if asset.state<>'pending' then raise exception 'Saved originals cannot be discarded'; end if;
  if exists (select 1 from storage.objects where bucket_id='character-originals' and name=asset.object_path) then
    raise exception 'Remove the unfinished file through Storage before discarding';
  end if;
  update public.original_assets set state='cancelled' where id=asset.id;
end; $$;

create or replace function imagineos_story_private.save_story_draft(
  p_page_id uuid,p_source_id uuid,p_revision integer,p_scene text,p_dialogue text,p_narration text
) returns integer language plpgsql security definer set search_path='' as $$
declare
  v_family uuid;
  v_page public.story_page_drafts;
  v_revision integer;
begin
  v_family:=imagineos_child_private.asset_family(p_source_id);
  if p_page_id is null or p_source_id is null or p_revision is null or p_revision<0 or
      p_scene is null or char_length(p_scene)>2000 or p_dialogue is null or char_length(p_dialogue)>20000 or
      p_narration is null or char_length(p_narration)>20000 then raise exception 'Invalid draft'; end if;
  if not exists(select 1 from public.original_assets a join public.character_versions v on v.id=a.version_id
      join public.characters c on c.id=v.character_id where a.id=p_source_id and a.family_id=v_family
      and a.state='ready' and not v.deletion_requested and not c.deletion_requested) then raise insufficient_privilege; end if;
  select * into v_page from public.story_page_drafts where page_id=p_page_id for update;
  if found then
    if v_page.family_id<>v_family or v_page.source_id<>p_source_id then raise insufficient_privilege; end if;
    -- A lost response can replay the exact same save, without a new revision.
    if v_page.scene=p_scene and v_page.dialogue=p_dialogue and v_page.narration=p_narration then return v_page.revision; end if;
    if v_page.revision<>p_revision then raise exception 'Draft changed on another device'; end if;
    update public.story_page_drafts set scene=p_scene,dialogue=p_dialogue,narration=p_narration,
      revision=revision+1,updated_at=now() where page_id=p_page_id returning revision into v_revision;
    return v_revision;
  end if;
  if p_revision<>0 then raise exception 'Draft no longer exists'; end if;
  insert into public.story_page_drafts(page_id,family_id,source_id,scene,dialogue,narration)
    values(p_page_id,v_family,p_source_id,p_scene,p_dialogue,p_narration);
  return 1;
end;
$$;

create or replace function imagineos_story_private.save_story_project(
  p_id uuid,p_child_id uuid,p_revision integer,p_title text,p_format text,p_panels jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  v_family uuid; v_story public.story_projects; v_panel jsonb; v_old public.story_panels;
  v_source record; v_position integer:=0; v_revision integer; v_ids uuid[]:='{}';
begin
  v_family:=imagineos_child_private.creator_family(p_child_id);
  if p_id is null or p_revision is null or p_revision<0 or p_title is null or char_length(p_title)>160
    or p_format is null or p_format not in ('illustrated','comic','strip')
    or p_panels is null or jsonb_typeof(p_panels)<>'array' or jsonb_array_length(p_panels)>24
    or octet_length(p_panels::text)>4194304 then raise exception 'Invalid story'; end if;
  -- Serialize equal IDs even when submitted by different families.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,13));
  select * into v_story from public.story_projects where id=p_id for update;
  if found then
    if v_story.family_id<>v_family or v_story.child_id<>p_child_id then raise insufficient_privilege; end if;
    if v_story.deleted then raise exception 'Story was deleted'; end if;
    if v_story.title=p_title and v_story.format=p_format and
      imagineos_story_private.project_panels(p_id)=p_panels then return v_story.revision; end if;
    if v_story.revision<>p_revision then raise exception 'Story changed on another device'; end if;
  else
    if p_revision<>0 then raise exception 'Story no longer exists'; end if;
    insert into public.story_projects(id,family_id,child_id,title,format)
      values(p_id,v_family,p_child_id,p_title,p_format) returning * into v_story;
  end if;
  for v_panel in select value from jsonb_array_elements(p_panels) loop
    if jsonb_typeof(v_panel)<>'object' or not (v_panel ?& array['id','reference','scene','dialogue','narration'])
      or v_panel-array['id','reference','scene','dialogue','narration']<>'{}'::jsonb
      or jsonb_typeof(v_panel->'id')<>'string' or jsonb_typeof(v_panel->'reference')<>'object'
      or not ((v_panel->'reference') ?& array['character_id','version_id','asset_id','sha256'])
      or jsonb_typeof(v_panel#>'{reference,character_id}')<>'string'
      or jsonb_typeof(v_panel#>'{reference,version_id}')<>'string'
      or jsonb_typeof(v_panel#>'{reference,asset_id}')<>'string'
      or jsonb_typeof(v_panel#>'{reference,sha256}')<>'string'
      or (v_panel->'reference')-array['character_id','version_id','asset_id','sha256']<>'{}'::jsonb
      or jsonb_typeof(v_panel->'scene')<>'string' or char_length(v_panel->>'scene')>2000
      or jsonb_typeof(v_panel->'dialogue')<>'string' or char_length(v_panel->>'dialogue')>20000
      or jsonb_typeof(v_panel->'narration')<>'string' or char_length(v_panel->>'narration')>20000
      or coalesce(v_panel#>>'{reference,sha256}','')!~'^[a-f0-9]{64}$' then raise exception 'Invalid panel'; end if;
    if (v_panel->>'id')::uuid=any(v_ids) then raise exception 'Duplicate panel'; end if;
    v_ids:=array_append(v_ids,(v_panel->>'id')::uuid);
    select * into v_old from public.story_panels where id=(v_panel->>'id')::uuid;
    if found and (v_old.story_id<>p_id or v_old.asset_id<>(v_panel#>>'{reference,asset_id}')::uuid
      or v_old.character_id<>(v_panel#>>'{reference,character_id}')::uuid
      or v_old.version_id<>(v_panel#>>'{reference,version_id}')::uuid
      or v_old.sha256<>v_panel#>>'{reference,sha256}') then raise insufficient_privilege; end if;
    if not found or v_old.source_id is not null then
      select a.id,a.sha256,v.id as version_id,v.character_id,v.name,v.version_number into v_source
        from public.original_assets a join public.character_versions v on v.id=a.version_id
        join public.characters c on c.id=v.character_id
        where a.id=(v_panel#>>'{reference,asset_id}')::uuid and a.family_id=v_family
        and a.state='ready' and c.child_profile_id=p_child_id and not c.deletion_requested and not v.deletion_requested
        for share of a,v,c;
      if not found or v_source.sha256<>v_panel#>>'{reference,sha256}'
        or v_source.version_id<>(v_panel#>>'{reference,version_id}')::uuid
        or v_source.character_id<>(v_panel#>>'{reference,character_id}')::uuid then raise insufficient_privilege; end if;
    end if;
    if v_old.id is null then
      insert into public.story_panels(id,story_id,family_id,position,source_id,asset_id,character_id,version_id,sha256,
        character_name,version_number,scene,dialogue,narration)
        values((v_panel->>'id')::uuid,p_id,v_family,v_position,v_source.id,v_source.id,v_source.character_id,
          v_source.version_id,v_source.sha256,v_source.name,v_source.version_number,
          v_panel->>'scene',v_panel->>'dialogue',v_panel->>'narration');
    else
      update public.story_panels set position=v_position,scene=v_panel->>'scene',dialogue=v_panel->>'dialogue',
        narration=v_panel->>'narration' where id=v_old.id;
    end if;
    v_position:=v_position+1;
  end loop;
  delete from public.story_panels where story_id=p_id and not(id=any(v_ids));
  update public.story_projects set title=p_title,format=p_format,
    revision=case when p_revision=0 then 1 else revision+1 end,updated_at=now()
    where id=p_id returning revision into v_revision;
  return v_revision;
end;
$$;
