-- Run inside a transaction after binding imagineos.test_parent_a/b and
-- imagineos.test_session_a/b to fictional fixtures. Roll back afterward.
do $$
declare
  a uuid := current_setting('imagineos.test_parent_a')::uuid;
  b uuid := current_setting('imagineos.test_parent_b')::uuid;
  sa uuid := current_setting('imagineos.test_session_a')::uuid;
  sb uuid := current_setting('imagineos.test_session_b')::uuid;
  family uuid;
  v_secret uuid;
  replacement uuid;
begin
  select id into family from public.families where parent_user_id=a;
  perform public.manage_parent_provider(a,sa,'save','openai','sk-fictional-not-a-provider-key');
  select secret_id into v_secret from imagineos_private.provider_connections where family_id=family;
  assert v_secret is not null, 'connection missing';
  assert (select decrypted_secret = 'sk-fictional-not-a-provider-key' and secret <> decrypted_secret
    from vault.decrypted_secrets where id=v_secret), 'credential must be encrypted at rest';
  assert jsonb_array_length(public.manage_parent_provider(a,sa,'list'))=1;
  assert public.manage_parent_provider(b,sb,'list')='[]'::jsonb, 'foreign family leaked';
  assert not has_function_privilege('authenticated','public.manage_parent_provider(uuid,uuid,text,text,text)','EXECUTE');
  assert not has_function_privilege('anon','public.manage_parent_provider(uuid,uuid,text,text,text)','EXECUTE');
  assert not has_schema_privilege('authenticated','imagineos_private','USAGE');
  perform public.manage_parent_provider(a,sa,'save','openai','sk-fictional-replacement-key');
  select secret_id into replacement from imagineos_private.provider_connections where family_id=family;
  assert replacement <> v_secret;
  assert not exists (select 1 from vault.secrets where id=v_secret), 'old secret retained';
  perform public.manage_parent_provider(a,sa,'disconnect','openai');
  assert not exists (select 1 from vault.secrets where id=replacement), 'disconnected secret retained';
  begin
    perform public.manage_parent_provider(a,gen_random_uuid(),'list');
    raise exception 'revoked session accepted';
  exception when others then
    if sqlerrm='revoked session accepted' then raise; end if;
  end;
  delete from imagineos_private.provider_connection_limits where family_id=family;
  for i in 1..10 loop
    assert public.manage_parent_provider(a,sa,'attempt')='true'::jsonb;
  end loop;
  assert public.manage_parent_provider(a,sa,'attempt')='false'::jsonb, 'attempt quota exceeded';
  perform public.manage_parent_provider(a,sa,'save','gemini','AIza-fictional-api-key-never-used');
  select secret_id into v_secret from imagineos_private.provider_connections where family_id=family;
  delete from public.families where id=family;
  assert not exists (select 1 from vault.secrets where id=v_secret), 'family deletion retained secret';
end;
$$;
select 'PASS: encrypted storage, replacement/disconnect cleanup, family isolation, RPC denial, revoked-session denial, atomic attempt quota and family deletion' as checks;
