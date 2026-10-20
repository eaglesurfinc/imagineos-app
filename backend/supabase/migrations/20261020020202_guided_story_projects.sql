-- Guided original-artwork stories. No provider access or generated content.
create table public.story_projects (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid not null references public.child_profiles(id) on delete cascade,
  title text not null check (char_length(title)<=160),
  format text not null check (format in ('illustrated','comic','strip')),
  revision integer not null default 1 check (revision>0),
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(id,family_id)
);
create index story_projects_family_updated_idx on public.story_projects(family_id,updated_at desc);
create index story_projects_child_idx on public.story_projects(child_id);
create table public.story_panels (
  id uuid primary key,
  story_id uuid not null,
  family_id uuid not null,
  position integer not null check (position between 0 and 23),
  -- A deliberate source deletion removes artwork, not the child's story words.
  source_id uuid references public.original_assets(id) on delete set null,
  asset_id uuid not null,
  character_id uuid not null,
  version_id uuid not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  character_name text not null,
  version_number integer not null check (version_number>0),
  scene text not null check (char_length(scene)<=2000),
  dialogue text not null check (char_length(dialogue)<=20000),
  narration text not null check (char_length(narration)<=20000),
  foreign key(story_id,family_id) references public.story_projects(id,family_id) on delete cascade,
  unique(story_id,position) deferrable initially deferred,
  check (source_id is null or source_id=asset_id)
);
create index story_panels_source_idx on public.story_panels(source_id);
create index story_panels_family_idx on public.story_panels(family_id);
alter table public.story_projects enable row level security;
alter table public.story_panels enable row level security;
revoke all on public.story_projects,public.story_panels from public,anon,authenticated;
grant select on public.story_projects,public.story_panels to authenticated;
create policy own_stories on public.story_projects for select to authenticated using (
  not deleted and exists(select 1 from public.families f where f.id=family_id and f.parent_user_id=(select auth.uid())));
create policy own_story_panels on public.story_panels for select to authenticated using (
  exists(select 1 from public.story_projects s where s.id=story_id and s.family_id=story_panels.family_id));

-- Internal payload excludes presentation metadata and preserves every string.
create function imagineos_story_private.project_panels(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',jsonb_build_object(
    'character_id',p.character_id,'version_id',p.version_id,'asset_id',p.asset_id,'sha256',p.sha256),
    'scene',p.scene,'dialogue',p.dialogue,'narration',p.narration) order by p.position),'[]'::jsonb)
  from public.story_panels p where p.story_id=p_id;
$$;
revoke all on function imagineos_story_private.project_panels(uuid) from public,anon,authenticated;

create function imagineos_story_private.save_story_project(
  p_id uuid,p_child_id uuid,p_revision integer,p_title text,p_format text,p_panels jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  v_family uuid; v_story public.story_projects; v_panel jsonb; v_old public.story_panels;
  v_source record; v_position integer:=0; v_revision integer; v_ids uuid[]:='{}';
begin
  if auth.uid() is null or not exists(select 1 from auth.sessions
    where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid()) then raise insufficient_privilege; end if;
  select f.id into v_family from public.families f join public.child_profiles ch on ch.family_id=f.id
    where ch.id=p_child_id and f.parent_user_id=auth.uid() for update of f;
  if v_family is null then raise insufficient_privilege; end if;
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
revoke all on function imagineos_story_private.save_story_project(uuid,uuid,integer,text,text,jsonb) from public,anon,authenticated;
grant execute on function imagineos_story_private.save_story_project(uuid,uuid,integer,text,text,jsonb) to authenticated;
create function public.save_story_project(p_id uuid,p_child_id uuid,p_revision integer,p_title text,p_format text,p_panels jsonb)
returns integer language sql security invoker set search_path='' as $$
  select imagineos_story_private.save_story_project(p_id,p_child_id,p_revision,p_title,p_format,p_panels);
$$;
revoke all on function public.save_story_project(uuid,uuid,integer,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_story_project(uuid,uuid,integer,text,text,jsonb) to authenticated;

create function imagineos_story_private.delete_story_project(p_id uuid,p_revision integer)
returns void language plpgsql security definer set search_path='' as $$
declare v_family uuid; v_story public.story_projects;
begin
  if auth.uid() is null or not exists(select 1 from auth.sessions
    where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid()) then raise insufficient_privilege; end if;
  select id into v_family from public.families where parent_user_id=auth.uid() for update;
  select * into v_story from public.story_projects where id=p_id for update;
  if not found or v_story.family_id<>v_family or v_family is null then raise insufficient_privilege; end if;
  if v_story.deleted then return; end if;
  if p_revision is null or p_revision<>v_story.revision then raise exception 'Story changed on another device'; end if;
  delete from public.story_panels where story_id=p_id;
  -- A minimal tombstone prevents an interrupted create retry resurrecting a deletion.
  update public.story_projects set deleted=true,title='',revision=revision+1,updated_at=now() where id=p_id;
end;
$$;
revoke all on function imagineos_story_private.delete_story_project(uuid,integer) from public,anon,authenticated;
grant execute on function imagineos_story_private.delete_story_project(uuid,integer) to authenticated;
create function public.delete_story_project(p_id uuid,p_revision integer) returns void
language sql security invoker set search_path='' as $$ select imagineos_story_private.delete_story_project(p_id,p_revision); $$;
revoke all on function public.delete_story_project(uuid,integer) from public,anon,authenticated;
grant execute on function public.delete_story_project(uuid,integer) to authenticated;

create view public.story_project_snapshots with (security_invoker=true) as
select s.id,s.child_id,s.title,s.format,s.revision,s.updated_at,
  coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',jsonb_build_object(
    'character_id',p.character_id,'version_id',p.version_id,'asset_id',p.asset_id,'sha256',p.sha256),
    'character_name',p.character_name,'version_number',p.version_number,
    'source_available',p.source_id is not null,'scene',p.scene,'dialogue',p.dialogue,'narration',p.narration)
    order by p.position) filter(where p.id is not null),'[]'::jsonb) as panels
from public.story_projects s left join public.story_panels p on p.story_id=s.id group by s.id;
revoke all on public.story_project_snapshots from public,anon,authenticated;
grant select on public.story_project_snapshots to authenticated;
