-- Only the authenticated server function can manage these encrypted credentials.
-- No browser role can read a key, call this RPC, or write connection metadata.
create table imagineos_private.provider_connections (
  family_id uuid not null references public.families(id) on delete cascade,
  provider text not null check (provider in ('openai','claude','gemini')),
  secret_id uuid not null unique references vault.secrets(id),
  connected_at timestamptz not null default now(),
  primary key (family_id, provider)
);
create table imagineos_private.provider_connection_limits (
  family_id uuid primary key references public.families(id) on delete cascade,
  window_start timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0)
);
alter table imagineos_private.provider_connections enable row level security;
alter table imagineos_private.provider_connection_limits enable row level security;
revoke all on imagineos_private.provider_connections,
  imagineos_private.provider_connection_limits from public, anon, authenticated;

-- Deletion of a connection/family also removes its Vault entry. Keys do not
-- outlive account removal, and replacing a key is a single transaction.
create function imagineos_private.erase_provider_secret() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from vault.secrets where id = old.secret_id;
  return old;
end;
$$;
revoke all on function imagineos_private.erase_provider_secret() from public, anon, authenticated;
create trigger erase_provider_secret after delete on imagineos_private.provider_connections
for each row execute function imagineos_private.erase_provider_secret();

create function imagineos_private.manage_parent_provider(
  p_parent_id uuid, p_session_id uuid, p_action text,
  p_provider text default null, p_secret text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_family uuid;
  v_secret uuid;
  v_attempts integer;
  v_result jsonb;
begin
  -- The caller is service_role, after Auth has validated the caller's JWT.
  -- Check its real session too: a signed-out/revoked JWT is insufficient.
  if not exists (select 1 from auth.sessions where id = p_session_id
      and user_id = p_parent_id) then raise exception 'Session unavailable'; end if;
  select id into v_family from public.families where parent_user_id = p_parent_id for update;
  if v_family is null then raise exception 'Family unavailable'; end if;
  if p_action = 'list' then
    select coalesce(jsonb_agg(jsonb_build_object('provider',provider,
      'connected_at',connected_at) order by provider),'[]'::jsonb)
      into v_result from imagineos_private.provider_connections where family_id = v_family;
    return v_result;
  end if;
  if p_action = 'attempt' then
    insert into imagineos_private.provider_connection_limits(family_id,attempts)
      values (v_family,1)
    on conflict (family_id) do update set
      attempts = case when provider_connection_limits.window_start < now() - interval '1 hour'
        then 1 else provider_connection_limits.attempts + 1 end,
      window_start = case when provider_connection_limits.window_start < now() - interval '1 hour'
        then now() else provider_connection_limits.window_start end
    returning attempts into v_attempts;
    return to_jsonb(v_attempts <= 10);
  end if;
  if p_provider is null or p_provider not in ('openai','claude','gemini') then
    raise exception 'Invalid provider';
  end if;
  if p_action = 'disconnect' then
    delete from imagineos_private.provider_connections where family_id=v_family and provider=p_provider;
    return 'true'::jsonb;
  elsif p_action = 'save' then
    if p_secret is null or octet_length(p_secret) not between 16 and 2048 then
      raise exception 'Invalid credential';
    end if;
    delete from imagineos_private.provider_connections where family_id=v_family and provider=p_provider;
    select vault.create_secret(p_secret) into v_secret;
    insert into imagineos_private.provider_connections(family_id,provider,secret_id)
      values (v_family,p_provider,v_secret);
    return 'true'::jsonb;
  end if;
  raise exception 'Invalid action';
end;
$$;
revoke all on function imagineos_private.manage_parent_provider(uuid,uuid,text,text,text)
  from public, anon, authenticated;
grant usage on schema imagineos_private to service_role;
grant execute on function imagineos_private.manage_parent_provider(uuid,uuid,text,text,text) to service_role;

-- Invoker wrapper: privileged logic remains in a non-exposed schema.
create function public.manage_parent_provider(
  p_parent_id uuid, p_session_id uuid, p_action text,
  p_provider text default null, p_secret text default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select imagineos_private.manage_parent_provider(p_parent_id,p_session_id,p_action,p_provider,p_secret);
$$;
revoke all on function public.manage_parent_provider(uuid,uuid,text,text,text)
  from public, anon, authenticated;
grant execute on function public.manage_parent_provider(uuid,uuid,text,text,text) to service_role;
