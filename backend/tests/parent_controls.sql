-- Bind imagineos.test_parent_a to the generated adult@example.invalid fixture.
-- Always run in a transaction and ROLLBACK; never use a real family.
do $$
declare
  v_parent uuid:=current_setting('imagineos.test_parent_a')::uuid;
  v_family uuid; v_session uuid; v_grant text:=repeat('a',64); v_blocked boolean:=false;
begin
  if not exists(select 1 from auth.users where id=v_parent and email like 'adult-%@example.invalid')
    then raise exception 'Fictional fixture required'; end if;
  select id into v_family from public.families where parent_user_id=v_parent;
  select id into v_session from auth.sessions where user_id=v_parent order by created_at desc limit 1;
  if v_family is null or v_session is null then raise exception 'Fixture session required'; end if;
  if has_function_privilege('authenticated','public.parent_controls(uuid,uuid,text,text)','execute')
    or has_function_privilege('anon','public.parent_controls(uuid,uuid,text,text)','execute')
    then raise exception 'Public parent capability issuer'; end if;
  perform public.parent_controls(v_parent,v_session,'unlock',v_grant);
  if public.parent_controls(v_parent,v_session,'overview',v_grant) is null then
    raise exception 'Valid grant rejected'; end if;
  update imagineos_private.parent_access set expires_at=now()-interval '1 second' where session_id=v_session;
  if public.parent_controls(v_parent,v_session,'overview',v_grant) is not null then
    raise exception 'Expired grant accepted'; end if;
  perform public.parent_controls(v_parent,v_session,'unlock',v_grant);
  begin
    perform public.parent_controls(v_parent,v_session,'delete_ready',v_grant);
  exception when insufficient_privilege then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'Deletion without request accepted'; end if;
end; $$;
do $$
declare v_parent uuid:=current_setting('imagineos.test_parent_a')::uuid;
  v_family uuid; v_session uuid; v_asset public.original_assets; v_blocked boolean:=false;
begin
  select id into v_family from public.families where parent_user_id=v_parent;
  select id into v_session from auth.sessions where user_id=v_parent order by created_at desc limit 1;
  select * into v_asset from public.original_assets where family_id=v_family limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_parent,'session_id',v_session,'role','authenticated')::text,true);
  insert into imagineos_private.family_deletions(family_id) values(v_family);
  begin
    insert into public.child_profiles(family_id,nickname) values(v_family,'Must be blocked');
  exception when raise_exception then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'Pending deletion allowed a new child'; end if;
  if imagineos_upload_private.pending_original(v_asset.object_path) then raise exception 'Pending deletion allowed upload'; end if;
  v_blocked:=false;
  begin
    update public.original_assets set state='pending' where id=v_asset.id;
  exception when raise_exception then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'Pending deletion allowed save'; end if;
end; $$;
select 'PASS: server grant expiry, private issuer and pending-deletion write/upload fences' as result;
