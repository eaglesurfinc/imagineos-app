-- Explicit removal is separate from immutable drawing updates. Files must be
-- removed through Storage before deleting their SQL references.
alter table public.characters add column deletion_requested boolean not null default false;
alter table public.characters add column last_version_number integer not null default 0;
update public.characters c set last_version_number=(
  select coalesce(max(v.version_number),0) from public.character_versions v where v.character_id=c.id);
alter table public.character_versions add column deletion_requested boolean not null default false;
alter table public.original_assets drop constraint original_assets_state_check;
alter table public.original_assets add constraint original_assets_state_check
  check (state in ('pending','ready','cancelled','deleting'));

-- Minimal retry tombstones contain no drawing, character name, or checksum.
-- They prevent a stale initial-upload retry from recreating deleted artwork.
create table imagineos_upload_private.deleted_original_requests (
  request_id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  deleted_at timestamptz not null default now()
);
create index deleted_original_requests_family_idx on imagineos_upload_private.deleted_original_requests(family_id);
alter table imagineos_upload_private.deleted_original_requests enable row level security;
revoke all on imagineos_upload_private.deleted_original_requests from public, anon, authenticated;

create function imagineos_upload_private.guard_new_version()
returns trigger language plpgsql security invoker set search_path='' as $$
declare character public.characters%rowtype;
begin
  select * into character from public.characters where id=new.character_id for update;
  if not found or character.deletion_requested then
    raise exception 'This character is being deleted';
  end if;
  -- Never reuse a removed version's number.
  new.version_number := character.last_version_number+1;
  update public.characters set last_version_number=new.version_number where id=character.id;
  return new;
end; $$;
create trigger guard_new_version before insert on public.character_versions
  for each row execute function imagineos_upload_private.guard_new_version();

create function imagineos_upload_private.guard_deleted_request()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if exists (select 1 from imagineos_upload_private.deleted_original_requests where request_id=new.id) then
    raise exception 'This original was deleted';
  end if;
  return new;
end; $$;
create trigger guard_deleted_request before insert on public.original_assets
  for each row execute function imagineos_upload_private.guard_deleted_request();

create or replace view public.original_uploads with (security_invoker=true) as
  select a.id as request_id, a.family_id, c.child_profile_id, c.id as character_id,
    v.id as version_id, v.version_number, v.name, a.object_path, a.mime_type,
    a.byte_size, a.sha256, a.state, a.created_at, c.deletion_requested as deleting_character
  from public.original_assets a
  join public.character_versions v on v.id=a.version_id and v.family_id=a.family_id
  join public.characters c on c.id=v.character_id and c.family_id=v.family_id;

create function imagineos_upload_private.begin_character_deletion(p_character_id uuid, p_version_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare family uuid; character public.characters%rowtype; paths jsonb;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  -- Match reservation lock order: family, character, then assets.
  select id into family from public.families where parent_user_id=auth.uid() for update;
  select * into character from public.characters where id=p_character_id and family_id=family for update;
  -- Foreign and already removed IDs are indistinguishable no-ops.
  if not found then return '[]'::jsonb; end if;
  if p_version_id is null then
    update public.characters set deletion_requested=true where id=character.id;
  else
    if character.deletion_requested then raise exception 'Finish deleting the whole character'; end if;
    perform id from public.character_versions where id=p_version_id and character_id=character.id;
    if not found then return '[]'::jsonb; end if;
    if not exists (
      select 1 from public.character_versions v join public.original_assets a on a.version_id=v.id
      where v.character_id=character.id and v.id<>p_version_id and a.state='ready'
    ) then raise exception 'Use Delete character to remove its last saved version'; end if;
  end if;
  perform a.id from public.original_assets a join public.character_versions v on v.id=a.version_id
    where v.character_id=character.id and (p_version_id is null or v.id=p_version_id) for update of a;
  update public.character_versions set deletion_requested=true
    where character_id=character.id and (p_version_id is null or id=p_version_id);
  insert into imagineos_upload_private.deleted_original_requests(request_id,family_id)
    select a.id,a.family_id from public.original_assets a join public.character_versions v on v.id=a.version_id
    where v.character_id=character.id and (p_version_id is null or v.id=p_version_id)
    on conflict (request_id) do nothing;
  update public.original_assets a set state='deleting' from public.character_versions v
    where v.id=a.version_id and v.character_id=character.id and (p_version_id is null or v.id=p_version_id);
  select coalesce(jsonb_agg(a.object_path order by a.object_path),'[]'::jsonb) into paths
    from public.original_assets a join public.character_versions v on v.id=a.version_id
    where v.character_id=character.id and (p_version_id is null or v.id=p_version_id);
  return paths;
end; $$;

create function imagineos_upload_private.finish_character_deletion(p_character_id uuid, p_version_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare family uuid; character public.characters%rowtype; marked boolean;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select id into family from public.families where parent_user_id=auth.uid() for update;
  select * into character from public.characters where id=p_character_id and family_id=family for update;
  if not found then return; end if;
  if p_version_id is null then
    marked := character.deletion_requested;
  else
    select deletion_requested into marked from public.character_versions
      where id=p_version_id and character_id=character.id;
    if not found then return; end if;
  end if;
  if not marked then raise exception 'Confirm deletion first'; end if;
  perform a.id from public.original_assets a join public.character_versions v on v.id=a.version_id
    where v.character_id=character.id and (p_version_id is null or v.id=p_version_id) for update of a;
  if exists (
    select 1 from storage.objects o join public.original_assets a on a.object_path=o.name
    join public.character_versions v on v.id=a.version_id
    where o.bucket_id='character-originals' and v.character_id=character.id
      and (p_version_id is null or v.id=p_version_id)
  ) then raise exception 'Remove all selected files through Storage before finishing deletion'; end if;
  if p_version_id is null then
    delete from public.characters where id=character.id;
  else
    delete from public.character_versions where id=p_version_id and character_id=character.id;
  end if;
end; $$;

create function imagineos_upload_private.deleting_original(p_path text)
returns boolean language plpgsql security definer set search_path='' as $$
declare status text;
begin
  if auth.uid() is null then return false; end if;
  select a.state into status from public.original_assets a join public.families f on f.id=a.family_id
    where a.object_path=p_path and f.parent_user_id=auth.uid() for update of a;
  return coalesce(status='deleting',false);
end; $$;
revoke all on function imagineos_upload_private.guard_new_version(),
  imagineos_upload_private.guard_deleted_request(),
  imagineos_upload_private.begin_character_deletion(uuid,uuid),
  imagineos_upload_private.finish_character_deletion(uuid,uuid),
  imagineos_upload_private.deleting_original(text) from public, anon, authenticated;
grant execute on function imagineos_upload_private.begin_character_deletion(uuid,uuid),
  imagineos_upload_private.finish_character_deletion(uuid,uuid),
  imagineos_upload_private.deleting_original(text) to authenticated;

create function public.begin_character_deletion(p_character_id uuid,p_version_id uuid default null)
returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_upload_private.begin_character_deletion(p_character_id,p_version_id);
$$;
create function public.finish_character_deletion(p_character_id uuid,p_version_id uuid default null)
returns void language sql security invoker set search_path='' as $$
  select imagineos_upload_private.finish_character_deletion(p_character_id,p_version_id);
$$;
revoke all on function public.begin_character_deletion(uuid,uuid),public.finish_character_deletion(uuid,uuid) from public,anon,authenticated;
grant execute on function public.begin_character_deletion(uuid,uuid),public.finish_character_deletion(uuid,uuid) to authenticated;

-- SELECT is required by Storage removal. These rows remain family-private.
alter policy originals_download on storage.objects using (
  bucket_id='character-originals' and exists (
    select 1 from public.original_assets a where a.object_path=name and a.state in ('pending','ready','deleting'))
);
create policy originals_delete_confirmed on storage.objects for delete to authenticated using (
  bucket_id='character-originals' and imagineos_upload_private.deleting_original(name)
);
