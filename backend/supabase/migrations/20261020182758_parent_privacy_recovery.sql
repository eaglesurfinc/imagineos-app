-- Policy selection is pending. This stores only a parent's collection pause;
-- no checkbox or login is treated as verified parental consent.
create table imagineos_private.family_privacy (
  family_id uuid primary key references public.families(id) on delete cascade,
  child_access_paused boolean not null default false
);
alter table imagineos_private.family_privacy enable row level security;
revoke all on imagineos_private.family_privacy from public,anon,authenticated;

create function imagineos_private.guard_child_access_pause() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.families where id=new.family_id for update;
  if exists(select 1 from imagineos_private.family_privacy where family_id=new.family_id and child_access_paused)
    then raise exception 'CHILD_ACCESS_PAUSED' using errcode='42501'; end if;
  return new;
end; $$;
revoke all on function imagineos_private.guard_child_access_pause() from public,anon,authenticated;
create trigger privacy_pause_guard before insert on imagineos_child_private.approvals
  for each row execute function imagineos_private.guard_child_access_pause();
create trigger privacy_pause_guard before insert on imagineos_child_private.sessions
  for each row execute function imagineos_private.guard_child_access_pause();

create function imagineos_private.parent_privacy(
 p_parent uuid,p_session uuid,p_grant_hash text,p_action text,p_paused boolean default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare f uuid; result jsonb;
begin
  if not exists(select 1 from auth.sessions where id=p_session and user_id=p_parent) then raise insufficient_privilege; end if;
  select id into f from public.families where parent_user_id=p_parent for update;
  if f is null or not exists(select 1 from imagineos_private.parent_access where session_id=p_session
    and family_id=f and token_hash=p_grant_hash and expires_at>clock_timestamp()) then raise insufficient_privilege; end if;
  if p_action not in ('privacy_status','privacy_pause','recovery_snapshot') then raise insufficient_privilege; end if;
  if p_action<>'privacy_status' and exists(select 1 from imagineos_private.family_deletions where family_id=f)
    then raise insufficient_privilege; end if;
  if p_action='privacy_pause' then
    if p_paused is null then raise exception 'Pause choice required'; end if;
    insert into imagineos_private.family_privacy(family_id,child_access_paused) values(f,p_paused)
      on conflict(family_id) do update set child_access_paused=excluded.child_access_paused;
    if p_paused then
      update imagineos_child_private.sessions set ended_at=clock_timestamp() where family_id=f and ended_at is null;
      update imagineos_child_private.approvals set redeem_before=clock_timestamp() where family_id=f;
    end if;
  end if;
  if p_action in ('privacy_status','privacy_pause') then
    return jsonb_build_object('family_id',f,'pilot_enabled',false,'consent_status','not_configured',
      'retention_status','not_configured','child_access_paused',coalesce((select child_access_paused
        from imagineos_private.family_privacy where family_id=f),false));
  end if;
  -- Bounded, complete export. Reject oversized families instead of truncating.
  if (select count(*) from public.child_profiles where family_id=f)>100
    or (select count(*) from public.original_assets where family_id=f and state='ready')>250
    or (select coalesce(sum(byte_size),0) from public.original_assets where family_id=f and state='ready')>33554432
    or (select count(*) from public.story_projects where family_id=f and not deleted)>200
    or (select count(*) from public.story_page_drafts where family_id=f)>500
    then raise exception 'Family exceeds portable backup limits' using errcode='54000'; end if;
  result:=jsonb_build_object('family_id',f,
    'children',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nickname',nickname) order by id)
      from public.child_profiles where family_id=f),'[]'::jsonb),
    'originals',coalesce((select jsonb_agg(jsonb_build_object('request_id',request_id,'character_id',character_id,
      'child_profile_id',child_profile_id,'version_id',version_id,'version_number',version_number,'name',name,
      'object_path',object_path,'sha256',sha256,'state',state,'deleting_character',deleting_character,
      'mime_type',mime_type,'byte_size',byte_size) order by child_profile_id,character_id,version_number)
      from public.original_uploads where family_id=f and state='ready' and not deleting_character),'[]'::jsonb),
    'stories',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'child_id',s.child_id,'title',s.title,
      'format',s.format,'revision',s.revision,'panels',s.panels) order by s.id)
      from public.story_project_snapshots s join public.story_projects p on p.id=s.id
      where p.family_id=f and not p.deleted),'[]'::jsonb),
    'pages',coalesce((select jsonb_agg(jsonb_build_object('page_id',page_id,'source_id',source_id,
      'character_id',character_id,'version_id',version_id,'sha256',sha256,'scene',scene,'dialogue',dialogue,
      'narration',narration,'revision',revision) order by page_id)
      from public.saved_story_drafts where family_id=f),'[]'::jsonb));
  if octet_length(result::text)>3145728 then raise exception 'Family exceeds portable backup limits' using errcode='54000'; end if;
  return result;
end; $$;
revoke all on function imagineos_private.parent_privacy(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function imagineos_private.parent_privacy(uuid,uuid,text,text,boolean) to service_role;
create function public.parent_privacy(p_parent uuid,p_session uuid,p_grant_hash text,p_action text,p_paused boolean default null)
returns jsonb language sql security invoker set search_path='' as $$
 select imagineos_private.parent_privacy(p_parent,p_session,p_grant_hash,p_action,p_paused);
$$;
revoke all on function public.parent_privacy(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.parent_privacy(uuid,uuid,text,text,boolean) to service_role;
