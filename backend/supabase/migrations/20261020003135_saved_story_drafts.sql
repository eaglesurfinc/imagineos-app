-- A saved draft uses original artwork. It is never an accepted AI illustration.
create table public.story_page_drafts (
  page_id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  source_id uuid not null references public.original_assets(id) on delete cascade,
  revision integer not null default 1 check (revision > 0),
  scene text not null check (char_length(scene) <= 2000),
  dialogue text not null check (char_length(dialogue) <= 20000),
  narration text not null check (char_length(narration) <= 20000),
  updated_at timestamptz not null default now()
);
create index story_page_drafts_family_idx on public.story_page_drafts(family_id);
create index story_page_drafts_source_idx on public.story_page_drafts(source_id,updated_at desc);
alter table public.story_page_drafts enable row level security;
revoke all on public.story_page_drafts from public,anon,authenticated;
grant select on public.story_page_drafts to authenticated;
create policy read_own_page_drafts on public.story_page_drafts for select to authenticated
  using (exists(select 1 from public.families where id=family_id and parent_user_id=(select auth.uid())));

create schema imagineos_story_private;
revoke all on schema imagineos_story_private from public,anon,authenticated;
grant usage on schema imagineos_story_private to authenticated;
create function imagineos_story_private.save_story_draft(
  p_page_id uuid,p_source_id uuid,p_revision integer,p_scene text,p_dialogue text,p_narration text
) returns integer language plpgsql security definer set search_path='' as $$
declare
  v_family uuid;
  v_page public.story_page_drafts;
  v_revision integer;
begin
  if auth.uid() is null or not exists(select 1 from auth.sessions
      where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid()) then raise insufficient_privilege; end if;
  select id into v_family from public.families where parent_user_id=auth.uid() for update;
  if v_family is null then raise insufficient_privilege; end if;
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
revoke all on function imagineos_story_private.save_story_draft(uuid,uuid,integer,text,text,text) from public,anon,authenticated;
grant execute on function imagineos_story_private.save_story_draft(uuid,uuid,integer,text,text,text) to authenticated;
create function public.save_story_draft(p_page_id uuid,p_source_id uuid,p_revision integer,p_scene text,p_dialogue text,p_narration text)
returns integer language sql security invoker set search_path='' as $$
  select imagineos_story_private.save_story_draft(p_page_id,p_source_id,p_revision,p_scene,p_dialogue,p_narration);
$$;
revoke all on function public.save_story_draft(uuid,uuid,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.save_story_draft(uuid,uuid,integer,text,text,text) to authenticated;

create view public.saved_story_drafts with (security_invoker=true) as
  select p.*,a.sha256,a.version_id,v.character_id,v.name,v.version_number
  from public.story_page_drafts p join public.original_assets a on a.id=p.source_id
  join public.character_versions v on v.id=a.version_id;
revoke all on public.saved_story_drafts from public,anon,authenticated;
grant select on public.saved_story_drafts to authenticated;
