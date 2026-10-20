-- Synthetic records and simulated accounting only. Bind the same fictional
-- parent/session settings as provider_connections.sql; always roll back.
do $$
declare
  a uuid:=current_setting('imagineos.test_parent_a')::uuid;
  b uuid:=current_setting('imagineos.test_parent_b')::uuid;
  sa uuid:=current_setting('imagineos.test_session_a')::uuid;
  sb uuid:=current_setting('imagineos.test_session_b')::uuid;
  f uuid;
  child uuid:=gen_random_uuid(); character uuid:=gen_random_uuid();
  version uuid:=gen_random_uuid(); source uuid:=gen_random_uuid();
  job uuid:=gen_random_uuid(); second uuid:=gen_random_uuid();
  trace uuid:=gen_random_uuid(); hash text:=repeat('a',64);
  reply jsonb;
begin
  select id into f from public.families where parent_user_id=a;
  assert not (select enabled from imagineos_private.illustration_control where singleton);
  reply:=public.reserve_illustration(a,sa,job,trace,hash,'openai',source,800000);
  assert reply->>'status'='disabled';
  assert not exists(select 1 from imagineos_private.illustration_jobs where family_id=f);
  insert into public.child_profiles(id,family_id,nickname) values(child,f,'Fictional ledger creator');
  insert into public.characters(id,family_id,child_profile_id) values(character,f,child);
  insert into public.character_versions(id,family_id,character_id,version_number,name)
    values(version,f,character,1,'Fictional ledger reference');
  insert into public.original_assets(id,version_id,family_id,object_path,mime_type,byte_size,sha256,state)
    values(source,version,f,f::text||'/fictional-ledger.png','image/png',8,hash,'ready');
  -- This is a transactional simulation, not live provider enablement.
  update imagineos_private.illustration_control set enabled=true,authorized_micros=1000000 where singleton;
  assert public.reserve_illustration(a,sa,job,trace,hash,'openai',source,800000)->>'status'='provider_unavailable';
  perform public.manage_parent_provider(a,sa,'save','openai','sk-fictional-ledger-key-never-used');
  assert public.reserve_illustration(a,sa,job,trace,hash,'openai',source,800000)->>'status'='quota_exhausted';
  update imagineos_private.illustration_family_limits set authorized_micros=1000000,daily_limit=2 where family_id=f;
  reply:=public.reserve_illustration(a,sa,job,trace,hash,'openai',source,800000);
  assert reply->>'status'='reserved' and reply->>'replay'='false';
  reply:=public.reserve_illustration(a,sa,job,gen_random_uuid(),hash,'openai',source,800000);
  assert reply->>'replay'='true' and (reply->>'trace_id')::uuid=trace;
  assert (select reserved_micros=800000 from imagineos_private.illustration_control where singleton);
  assert public.reserve_illustration(a,sa,job,trace,repeat('b',64),'openai',source,800000)->>'status'='conflict';
  assert public.reserve_illustration(a,sa,second,gen_random_uuid(),hash,'openai',source,300000)->>'status'='quota_exhausted';
  assert public.advance_illustration(f,job,'claim')='running';
  assert public.advance_illustration(f,job,'claim')='already_claimed';
  assert public.advance_illustration(f,job,'succeeded',200000)='succeeded';
  assert public.advance_illustration(f,job,'succeeded',200000)='succeeded';
  assert (select reserved_micros=0 and spent_micros=200000 from imagineos_private.illustration_control where singleton);
  assert public.reserve_illustration(a,sa,second,gen_random_uuid(),hash,'openai',source,400000)->>'status'='reserved';
  assert public.advance_illustration(f,second,'claim')='running';
  assert public.advance_illustration(f,second,'indeterminate')='indeterminate';
  assert (select reserved_micros=400000 from imagineos_private.illustration_control where singleton);
  assert public.advance_illustration(f,second,'claim')='already_claimed';
  assert public.advance_illustration(f,second,'failed',100000)='failed';
  assert (select reserved_micros=0 and spent_micros=300000 from imagineos_private.illustration_family_limits where family_id=f);
  assert public.reserve_illustration(a,sa,gen_random_uuid(),trace,hash,'openai',source,100000)->>'status'='quota_exhausted';
  assert public.reserve_illustration(b,sb,gen_random_uuid(),trace,hash,'openai',source,100000)->>'status'='reference_unavailable';
  update imagineos_private.illustration_control set enabled=false where singleton;
  assert public.reserve_illustration(a,sa,gen_random_uuid(),trace,hash,'openai',source,100000)->>'status'='disabled';
  assert not has_function_privilege('authenticated','public.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint)','EXECUTE');
  assert not has_function_privilege('authenticated','public.advance_illustration(uuid,uuid,text,bigint)','EXECUTE');
  assert not has_function_privilege('anon','public.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint)','EXECUTE');
end;
$$;
select 'PASS: default-off kill switch, owner/reference checks, zero-default funding, idempotency/conflicts, atomic reservation, one claim, settlement/replay, daily limits and unknown-cost hold' as checks;
