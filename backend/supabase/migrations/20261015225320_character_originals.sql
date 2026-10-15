create table public.characters (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_profile_id uuid not null references public.child_profiles(id),
  created_at timestamptz not null default now(),
  unique (id, family_id)
);
create index characters_family_idx on public.characters(family_id);
create index characters_child_idx on public.characters(child_profile_id);
create table public.character_versions (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null,
  family_id uuid not null,
  version_number integer not null check (version_number > 0),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  foreign key (character_id, family_id) references public.characters(id, family_id) on delete cascade,
  unique (character_id, version_number),
  unique (id, family_id)
);
create index character_versions_family_idx on public.character_versions(family_id);
create table public.original_assets (
  id uuid primary key, -- Client-generated retry key, never an ownership claim.
  version_id uuid not null unique,
  family_id uuid not null,
  object_path text not null unique,
  mime_type text not null check (mime_type in ('image/png','image/jpeg','image/webp')),
  byte_size integer not null check (byte_size between 1 and 5242880),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  state text not null default 'pending' check (state in ('pending','ready','cancelled')),
  created_at timestamptz not null default now(),
  foreign key (version_id, family_id) references public.character_versions(id, family_id) on delete cascade
);
create index original_assets_family_state_idx on public.original_assets(family_id,state);
alter table public.characters enable row level security;
alter table public.character_versions enable row level security;
alter table public.original_assets enable row level security;
revoke all on public.characters, public.character_versions, public.original_assets from anon, authenticated;
grant select on public.characters, public.character_versions, public.original_assets to authenticated;
create policy characters_read_family on public.characters for select to authenticated
  using (exists (select 1 from public.families f where f.id=family_id and f.parent_user_id=(select auth.uid())));
create policy versions_read_family on public.character_versions for select to authenticated
  using (exists (select 1 from public.families f where f.id=family_id and f.parent_user_id=(select auth.uid())));
create policy originals_read_family on public.original_assets for select to authenticated
  using (exists (select 1 from public.families f where f.id=family_id and f.parent_user_id=(select auth.uid())));

create view public.original_uploads with (security_invoker=true) as
  select a.id as request_id, a.family_id, c.child_profile_id, c.id as character_id,
    v.id as version_id, v.version_number, v.name, a.object_path, a.mime_type,
    a.byte_size, a.sha256, a.state, a.created_at
  from public.original_assets a
  join public.character_versions v on v.id=a.version_id and v.family_id=a.family_id
  join public.characters c on c.id=v.character_id and c.family_id=v.family_id;
revoke all on public.original_uploads from anon, authenticated;
grant select on public.original_uploads to authenticated;

-- Privileged state transitions live outside the exposed schema. Public wrappers
-- are invokers. Every implementation checks auth.uid() and database ownership.
create schema imagineos_upload_private;
revoke all on schema imagineos_upload_private from public, anon, authenticated;
grant usage on schema imagineos_upload_private to authenticated;

create function imagineos_upload_private.reserve_original(
  p_request_id uuid, p_child_id uuid, p_character_id uuid, p_name text,
  p_mime_type text, p_byte_size integer, p_sha256 text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare family uuid; character uuid; version uuid; number integer; existing public.original_uploads%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select f.id into family from public.families f join public.child_profiles ch on ch.family_id=f.id
    where ch.id=p_child_id and f.parent_user_id=auth.uid() for update of f;
  if family is null then raise insufficient_privilege; end if;
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

create function imagineos_upload_private.finish_original(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare asset public.original_assets%rowtype; metadata jsonb;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select a.* into asset from public.original_assets a join public.families f on f.id=a.family_id
    where a.id=p_request_id and f.parent_user_id=auth.uid() for update of a;
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

create function imagineos_upload_private.cancel_original(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare asset public.original_assets%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select a.* into asset from public.original_assets a join public.families f on f.id=a.family_id
    where a.id=p_request_id and f.parent_user_id=auth.uid() for update of a;
  if not found then raise insufficient_privilege; end if;
  if asset.state='cancelled' then return; end if;
  if asset.state<>'pending' then raise exception 'Saved originals cannot be discarded'; end if;
  if exists (select 1 from storage.objects where bucket_id='character-originals' and name=asset.object_path) then
    raise exception 'Remove the unfinished file through Storage before discarding';
  end if;
  update public.original_assets set state='cancelled' where id=asset.id;
end; $$;

-- Row locking prevents a concurrent delete/upload from racing publication.
create function imagineos_upload_private.pending_original(p_path text)
returns boolean language plpgsql security definer set search_path='' as $$
declare status text;
begin
  if auth.uid() is null then return false; end if;
  select a.state into status from public.original_assets a join public.families f on f.id=a.family_id
    where a.object_path=p_path and f.parent_user_id=auth.uid() for update of a;
  return coalesce(status='pending',false);
end; $$;

revoke all on all functions in schema imagineos_upload_private from public, anon, authenticated;
grant execute on all functions in schema imagineos_upload_private to authenticated;
create function public.reserve_original(p_request_id uuid,p_child_id uuid,p_character_id uuid,p_name text,p_mime_type text,p_byte_size integer,p_sha256 text)
returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_upload_private.reserve_original(p_request_id,p_child_id,p_character_id,p_name,p_mime_type,p_byte_size,p_sha256);
$$;
create function public.finish_original(p_request_id uuid) returns void language sql security invoker set search_path='' as $$
  select imagineos_upload_private.finish_original(p_request_id);
$$;
create function public.cancel_original(p_request_id uuid) returns void language sql security invoker set search_path='' as $$
  select imagineos_upload_private.cancel_original(p_request_id);
$$;
revoke all on function public.reserve_original(uuid,uuid,uuid,text,text,integer,text), public.finish_original(uuid), public.cancel_original(uuid) from public, anon, authenticated;
grant execute on function public.reserve_original(uuid,uuid,uuid,text,text,integer,text), public.finish_original(uuid), public.cancel_original(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values ('character-originals','character-originals',false,5242880,array['image/png','image/jpeg','image/webp']);
create policy originals_download on storage.objects for select to authenticated using (
  bucket_id='character-originals' and exists (
    select 1 from public.original_assets a where a.object_path=name and a.state in ('pending','ready'))
);
create policy originals_upload on storage.objects for insert to authenticated with check (
  bucket_id='character-originals' and imagineos_upload_private.pending_original(name)
);
create policy originals_discard_pending on storage.objects for delete to authenticated using (
  bucket_id='character-originals' and imagineos_upload_private.pending_original(name)
);
-- No UPDATE policy: originals cannot be overwritten, moved, or upserted.
