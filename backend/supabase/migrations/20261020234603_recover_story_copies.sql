-- Parent-confirmed imports may retain exact story text when artwork was already
-- deleted before backup. Missing art is never linked to another stored asset.
create function imagineos_private.recover_story_copy(
 p_parent uuid,p_session uuid,p_grant_hash text,p_story jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 f uuid; story_id uuid; child_id uuid; saved public.story_projects;
 panel jsonb; ref jsonb; source record; panel_id uuid; ids uuid[]:='{}';
 available boolean; resolved_source uuid; position integer:=0; expected jsonb; actual jsonb;
begin
 if not exists(select 1 from auth.sessions where id=p_session and user_id=p_parent) then raise insufficient_privilege; end if;
 select id into f from public.families where parent_user_id=p_parent for update;
 if f is null or not exists(select 1 from imagineos_private.parent_access where session_id=p_session
   and family_id=f and token_hash=p_grant_hash and expires_at>clock_timestamp())
   or exists(select 1 from imagineos_private.family_deletions where family_id=f) then raise insufficient_privilege; end if;
 if p_story is null or jsonb_typeof(p_story)<>'object'
   or not (p_story ?& array['id','child_id','title','format','revision','panels'])
   or p_story-array['id','child_id','title','format','revision','panels']<>'{}'::jsonb
   or jsonb_typeof(p_story->'id')<>'string' or jsonb_typeof(p_story->'child_id')<>'string'
   or jsonb_typeof(p_story->'title')<>'string' or char_length(p_story->>'title')>160
   or jsonb_typeof(p_story->'format')<>'string' or p_story->>'format' not in ('illustrated','comic','strip')
   or p_story->'revision'<>'0'::jsonb or jsonb_typeof(p_story->'panels')<>'array'
   or jsonb_array_length(p_story->'panels')>24 or octet_length(p_story::text)>4210688
   then raise exception 'Invalid recovery' using errcode='22023'; end if;
 story_id:=(p_story->>'id')::uuid; child_id:=(p_story->>'child_id')::uuid;
 if not exists(select 1 from public.child_profiles c where c.id=child_id and c.family_id=f) then raise insufficient_privilege; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(story_id::text,13));
 select * into saved from public.story_projects where id=story_id for update;
 if found then
   if saved.family_id<>f or saved.child_id<>child_id then raise insufficient_privilege; end if;
   if saved.deleted then raise exception 'Recovery conflict' using errcode='P0002'; end if;
   select jsonb_build_object('id',s.id,'child_id',s.child_id,'title',s.title,'format',s.format,'panels',s.panels)
     into actual from public.story_project_snapshots s where s.id=story_id;
   expected:=p_story-'revision';
   if actual is distinct from expected then raise exception 'Recovery conflict' using errcode='P0002'; end if;
   return jsonb_build_object('revision',saved.revision);
 end if;
 insert into public.story_projects(id,family_id,child_id,title,format)
   values(story_id,f,child_id,p_story->>'title',p_story->>'format');
 for panel in select value from jsonb_array_elements(p_story->'panels') loop
   if jsonb_typeof(panel)<>'object'
     or not (panel ?& array['id','reference','character_name','version_number','source_available','scene','dialogue','narration'])
     or panel-array['id','reference','character_name','version_number','source_available','scene','dialogue','narration']<>'{}'::jsonb
     or jsonb_typeof(panel->'id')<>'string' or jsonb_typeof(panel->'source_available')<>'boolean'
     or jsonb_typeof(panel->'reference')<>'object' or jsonb_typeof(panel->'character_name')<>'string'
     or char_length(btrim(panel->>'character_name'))<1 or char_length(panel->>'character_name')>80
     or jsonb_typeof(panel->'version_number')<>'number' or (panel->>'version_number')!~'^[0-9]+$'
     or (panel->>'version_number')::numeric not between 1 and 2147483647
     or jsonb_typeof(panel->'scene')<>'string' or char_length(panel->>'scene')>2000
     or jsonb_typeof(panel->'dialogue')<>'string' or char_length(panel->>'dialogue')>20000
     or jsonb_typeof(panel->'narration')<>'string' or char_length(panel->>'narration')>20000
     then raise exception 'Invalid recovery' using errcode='22023'; end if;
   ref:=panel->'reference';
   if not (ref ?& array['character_id','version_id','asset_id','sha256'])
     or ref-array['character_id','version_id','asset_id','sha256']<>'{}'::jsonb
     or jsonb_typeof(ref->'character_id')<>'string' or jsonb_typeof(ref->'version_id')<>'string'
     or jsonb_typeof(ref->'asset_id')<>'string' or jsonb_typeof(ref->'sha256')<>'string'
     or (ref->>'sha256')!~'^[a-f0-9]{64}$' then raise exception 'Invalid recovery' using errcode='22023'; end if;
   -- Validate opaque historical IDs too, but never resolve unavailable artwork.
   perform (ref->>'character_id')::uuid,(ref->>'version_id')::uuid,(ref->>'asset_id')::uuid;
   panel_id:=(panel->>'id')::uuid; available:=(panel->>'source_available')::boolean;
   if panel_id=any(ids) then raise exception 'Invalid recovery' using errcode='22023'; end if;
   ids:=array_append(ids,panel_id);
   resolved_source:=null;
   if available then
     select a.id,a.sha256,v.id as version_id,v.character_id,v.name,v.version_number into source
       from public.original_assets a join public.character_versions v on v.id=a.version_id
       join public.characters c on c.id=v.character_id
       where a.id=(ref->>'asset_id')::uuid and a.family_id=f and a.state='ready'
       and c.child_profile_id=child_id and not c.deletion_requested and not v.deletion_requested
       for share of a,v,c;
     if not found or source.sha256<>ref->>'sha256' or source.version_id<>(ref->>'version_id')::uuid
       or source.character_id<>(ref->>'character_id')::uuid or source.name<>panel->>'character_name'
       or source.version_number<>(panel->>'version_number')::integer then raise insufficient_privilege; end if;
     resolved_source:=source.id;
   end if;
   insert into public.story_panels(id,story_id,family_id,position,source_id,asset_id,character_id,version_id,sha256,
     character_name,version_number,scene,dialogue,narration)
     values(panel_id,story_id,f,position,resolved_source,
       (ref->>'asset_id')::uuid,(ref->>'character_id')::uuid,(ref->>'version_id')::uuid,ref->>'sha256',
       panel->>'character_name',(panel->>'version_number')::integer,panel->>'scene',panel->>'dialogue',panel->>'narration');
   position:=position+1;
 end loop;
 return jsonb_build_object('revision',1);
end; $$;
revoke all on function imagineos_private.recover_story_copy(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function imagineos_private.recover_story_copy(uuid,uuid,text,jsonb) to service_role;
create function public.recover_story_copy(p_parent uuid,p_session uuid,p_grant_hash text,p_story jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select imagineos_private.recover_story_copy(p_parent,p_session,p_grant_hash,p_story);
$$;
revoke all on function public.recover_story_copy(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.recover_story_copy(uuid,uuid,text,jsonb) to service_role;
