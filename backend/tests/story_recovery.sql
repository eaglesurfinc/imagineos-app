-- Self-contained fictional rows, no Storage or provider calls. Run this entire
-- file as one transaction; ROLLBACK is mandatory even after successful checks.
begin;
do $$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid();
 fa uuid; fb uuid; ca uuid:=gen_random_uuid(); cb uuid:=gen_random_uuid(); grant_hash text:=repeat('a',64);
 story uuid:=gen_random_uuid(); missing jsonb; available jsonb; value jsonb; changed jsonb; reply jsonb;
 character uuid:=gen_random_uuid(); version uuid:=gen_random_uuid(); asset uuid:=gen_random_uuid();
 foreign_character uuid:=gen_random_uuid(); foreign_version uuid:=gen_random_uuid(); foreign_asset uuid:=gen_random_uuid();
 words text:=E'  Exact fictional words 🌈\n<script>kept as words</script>  '; denied boolean;
begin
 assert not has_function_privilege('anon','public.recover_story_copy(uuid,uuid,text,jsonb)','execute');
 assert not has_function_privilege('authenticated','public.recover_story_copy(uuid,uuid,text,jsonb)','execute');
 assert has_function_privilege('service_role','public.recover_story_copy(uuid,uuid,text,jsonb)','execute');
 insert into auth.users(id,email,is_anonymous) values
   (a,'adult-recovery-'||a::text||'@example.invalid',false),(b,'adult-recovery-'||b::text||'@example.invalid',false);
 insert into auth.sessions(id,user_id) values(sa,a),(sb,b);
 select id into fa from public.families where parent_user_id=a;
 select id into fb from public.families where parent_user_id=b;
 insert into public.child_profiles(id,family_id,nickname) values(ca,fa,'Fictional recovery A'),(cb,fb,'Fictional recovery B');
 perform public.parent_controls(a,sa,'unlock',grant_hash);
 perform public.parent_controls(b,sb,'unlock',grant_hash);
 missing:=jsonb_build_object('id',gen_random_uuid(),'reference',jsonb_build_object('character_id',gen_random_uuid(),
   'version_id',gen_random_uuid(),'asset_id',gen_random_uuid(),'sha256',repeat('c',64)),
   'character_name','Deleted fictional character','version_number',3,'source_available',false,
   'scene',E'  walking\n','dialogue',words,'narration',E'\n End  ');
 value:=jsonb_build_object('id',story,'child_id',ca,'title','  Exact title  ','format','comic','revision',0,'panels',jsonb_build_array(missing));
 denied:=false;
 begin perform public.recover_story_copy(a,sa,repeat('b',64),value); exception when insufficient_privilege then denied:=true; end;
 assert denied;
 denied:=false;
 begin perform public.recover_story_copy(a,sb,grant_hash,value); exception when insufficient_privilege then denied:=true; end;
 assert denied;
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,jsonb_set(value,'{child_id}',to_jsonb(cb)));
 exception when insufficient_privilege then denied:=true; end;
 assert denied;
 assert not exists(select 1 from public.story_projects where id=story);
 reply:=public.recover_story_copy(a,sa,grant_hash,value);
 assert reply->>'revision'='1';
 assert public.recover_story_copy(a,sa,grant_hash,value)=reply;
 assert (select count(*)=1 from public.story_panels where story_id=story);
 assert (select source_id is null and dialogue=words and position=0 and version_number=3
   from public.story_panels where story_id=story);
 assert not exists(select 1 from public.original_assets where family_id=fa);
 assert (select panels->0->>'source_available'='false' from public.story_project_snapshots where id=story);
 -- Add one real metadata-only fixture reference, then put a missing panel after
 -- it. This checks that the previous source never leaks into a missing panel.
 insert into public.characters(id,family_id,child_profile_id) values(character,fa,ca),(foreign_character,fb,cb);
 insert into public.character_versions(id,family_id,character_id,version_number,name)
   values(version,fa,character,1,'Fictional present art'),(foreign_version,fb,foreign_character,1,'Fictional foreign art');
 insert into public.original_assets(id,version_id,family_id,object_path,mime_type,byte_size,sha256,state)
   values(asset,version,fa,fa::text||'/'||asset::text,'image/png',8,repeat('d',64),'ready'),
   (foreign_asset,foreign_version,fb,fb::text||'/'||foreign_asset::text,'image/png',8,repeat('e',64),'ready');
 available:=jsonb_set(missing,'{id}',to_jsonb(gen_random_uuid())) || jsonb_build_object(
   'reference',jsonb_build_object('character_id',character,'version_id',version,'asset_id',asset,'sha256',repeat('d',64)),
   'source_available',true,'character_name','Fictional present art','version_number',1);
 changed:=value || jsonb_build_object('id',gen_random_uuid(),'panels',jsonb_build_array(available,
   jsonb_set(missing,'{id}',to_jsonb(gen_random_uuid()))));
 perform public.recover_story_copy(a,sa,grant_hash,changed);
 assert (select source_id=asset from public.story_panels where story_id=(changed->>'id')::uuid and position=0);
 assert (select source_id is null and dialogue=words from public.story_panels where story_id=(changed->>'id')::uuid and position=1);
 -- Foreign live references cannot be imported; the whole story rolls back.
 changed:=value || jsonb_build_object('id',gen_random_uuid(),'panels',jsonb_build_array(
   available || jsonb_build_object('id',gen_random_uuid(),'reference',jsonb_build_object(
     'character_id',foreign_character,'version_id',foreign_version,'asset_id',foreign_asset,'sha256',repeat('e',64)),
     'character_name','Fictional foreign art')));
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,changed); exception when insufficient_privilege then denied:=true; end;
 assert denied;
 assert not exists(select 1 from public.story_projects where id=(changed->>'id')::uuid);
 -- Invalid input and duplicated panels never leave a partial story.
 changed:=value || jsonb_build_object('id',gen_random_uuid(),'panels',jsonb_build_array(missing,missing));
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,changed); exception when invalid_parameter_value or unique_violation then denied:=true; end;
 assert denied;
 assert not exists(select 1 from public.story_projects where id=(changed->>'id')::uuid);
 -- Ordinary creator edits retain missing artwork and exact new words. An old
 -- recovery replay cannot overwrite those edits or revive deliberate deletion.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sa,'role','authenticated')::text,true);
 perform public.save_story_project(story,ca,1,'Child edited title','strip',jsonb_build_array(
   (missing-array['character_name','version_number','source_available']) || jsonb_build_object('dialogue',words||E'\nMore exact words')));
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,value); exception when no_data_found then denied:=true; end;
 assert denied;
 assert (select title='Child edited title' and revision=2 from public.story_projects where id=story);
 perform public.delete_story_project(story,2);
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,value); exception when no_data_found then denied:=true; end;
 assert denied;
 update imagineos_private.parent_access set expires_at=clock_timestamp()-interval '1 second' where session_id=sa;
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,changed); exception when insufficient_privilege then denied:=true; end;
 assert denied;
 perform public.parent_controls(a,sa,'unlock',grant_hash);
 insert into imagineos_private.family_deletions(family_id) values(fa);
 denied:=false;
 begin perform public.recover_story_copy(a,sa,grant_hash,changed); exception when insufficient_privilege then denied:=true; end;
 assert denied;
 assert (select count(*)=0 from public.story_projects where family_id=fb);
end; $$;
select 'PASS: parent/session/grant/family fences, exact missing-art words/order, mixed references, atomic validation, replay/edit/deletion protection' as result;
rollback;
