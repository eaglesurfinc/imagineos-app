-- Run with an authorized development SQL connection. All fixtures roll back.
begin;
insert into auth.users (id, email, is_anonymous) values
 ('10000000-0000-4000-8000-000000000001', 'adult-a@example.invalid', false),
 ('10000000-0000-4000-8000-000000000002', 'adult-b@example.invalid', false),
 ('10000000-0000-4000-8000-000000000003', null, true);
insert into public.child_profiles(family_id, nickname)
 select id, 'Fictional creator' from public.families
 where parent_user_id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002');
select set_config('imagineos.test_family_b', id::text, true) from public.families
 where parent_user_id = '10000000-0000-4000-8000-000000000002';

do $$ begin
  if has_schema_privilege('authenticated', 'imagineos_private', 'usage') or
     has_function_privilege('authenticated', 'imagineos_private.provision_parent_family()', 'execute') then
    raise exception 'Client can access privileged trigger';
  end if;
end; $$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","user_metadata":{"role":"admin","family_id":"forged"}}', true);
do $$
declare affected integer;
begin
  if (select count(*) from public.families) <> 1 then raise exception 'Family read isolation failed'; end if;
  if (select count(*) from public.parent_profiles) <> 1 then raise exception 'Parent read isolation failed'; end if;
  if (select count(*) from public.child_profiles) <> 1 then raise exception 'Linked child read isolation failed'; end if;
  if exists (select 1 from public.families where id = current_setting('imagineos.test_family_b')::uuid) then
    raise exception 'Forged metadata escalated access';
  end if;
  begin
    insert into public.child_profiles(family_id, nickname) values (current_setting('imagineos.test_family_b')::uuid, 'Intruder');
    raise exception 'Foreign-family insert succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.child_profiles set family_id = current_setting('imagineos.test_family_b')::uuid;
    raise exception 'Child reassignment succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.families set parent_user_id = '10000000-0000-4000-8000-000000000002';
    raise exception 'Ownership reassignment succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.families(parent_user_id) values ('10000000-0000-4000-8000-000000000001');
    raise exception 'Client family provisioning succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.parent_profiles(id) values ('10000000-0000-4000-8000-000000000002');
    raise exception 'Client parent provisioning succeeded';
  exception when insufficient_privilege then null;
  end;
  update public.child_profiles set nickname = 'Blocked' where family_id = current_setting('imagineos.test_family_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Foreign update succeeded'; end if;
  delete from public.child_profiles where family_id = current_setting('imagineos.test_family_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Foreign delete succeeded'; end if;
  update public.child_profiles set nickname = 'Renamed fictional creator';
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'Own child update failed'; end if;
  insert into public.child_profiles(family_id, nickname) select id, 'Second fictional creator' from public.families;
  if (select count(*) from public.child_profiles) <> 2 then raise exception 'Own child insert failed'; end if;
end;
$$;

select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.families) <> 1 or (select count(*) from public.child_profiles) <> 1 then
    raise exception 'Second family isolation failed';
  end if;
end; $$;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}', true);
do $$ begin
  if exists (select 1 from public.families) or exists (select 1 from public.parent_profiles) or exists (select 1 from public.child_profiles) then
    raise exception 'Anonymous Auth user acquired family access';
  end if;
end; $$;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$ begin
  begin perform 1 from public.families; raise exception 'Unauthenticated family access succeeded';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.parent_profiles; raise exception 'Unauthenticated parent access succeeded';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.child_profiles; raise exception 'Unauthenticated child access succeeded';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;
select 'PASS: family reads/writes, linked resources, forged metadata, ownership, anonymous access' as result;
rollback;
