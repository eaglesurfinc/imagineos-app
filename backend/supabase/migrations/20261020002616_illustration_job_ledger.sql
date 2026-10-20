-- Durable accounting foundation. No grant permits browser writes or enables AI.
create table imagineos_private.illustration_control (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  authorized_micros bigint not null default 0 check (authorized_micros between 0 and 25000000),
  reserved_micros bigint not null default 0 check (reserved_micros >= 0),
  spent_micros bigint not null default 0 check (spent_micros >= 0),
  check (reserved_micros + spent_micros <= authorized_micros)
);
insert into imagineos_private.illustration_control(singleton) values (true);
create table imagineos_private.illustration_family_limits (
  family_id uuid primary key references public.families(id) on delete cascade,
  authorized_micros bigint not null default 0 check (authorized_micros between 0 and 25000000),
  reserved_micros bigint not null default 0 check (reserved_micros >= 0),
  spent_micros bigint not null default 0 check (spent_micros >= 0),
  daily_limit integer not null default 5 check (daily_limit between 0 and 20),
  usage_day date not null default (now() at time zone 'utc')::date,
  daily_attempts integer not null default 0 check (daily_attempts >= 0),
  check (reserved_micros + spent_micros <= authorized_micros)
);
create table imagineos_private.illustration_jobs (
  family_id uuid not null references public.families(id) on delete cascade,
  request_id uuid not null,
  trace_id uuid not null,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  provider text not null check (provider in ('openai','gemini')),
  source_id uuid references public.original_assets(id) on delete set null,
  state text not null default 'reserved' check (state in ('reserved','running','succeeded','rejected','failed','indeterminate')),
  max_cost_micros bigint not null check (max_cost_micros between 1 and 1000000),
  actual_cost_micros bigint check (actual_cost_micros >= 0 and actual_cost_micros <= max_cost_micros),
  attempts integer not null default 0 check (attempts between 0 and 1),
  created_at timestamptz not null default now(),
  primary key(family_id,request_id)
);
create index illustration_jobs_source_idx on imagineos_private.illustration_jobs(source_id);
alter table imagineos_private.illustration_control enable row level security;
alter table imagineos_private.illustration_family_limits enable row level security;
alter table imagineos_private.illustration_jobs enable row level security;
revoke all on imagineos_private.illustration_control,imagineos_private.illustration_family_limits,
  imagineos_private.illustration_jobs from public,anon,authenticated;

create function imagineos_private.reserve_illustration(
  p_parent_id uuid,p_session_id uuid,p_request_id uuid,p_trace_id uuid,
  p_fingerprint text,p_provider text,p_source_id uuid,p_max_cost_micros bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_family uuid;
  v_control imagineos_private.illustration_control;
  v_limit imagineos_private.illustration_family_limits;
  v_job imagineos_private.illustration_jobs;
begin
  if not exists(select 1 from auth.sessions where id=p_session_id and user_id=p_parent_id)
    then raise exception 'Session unavailable'; end if;
  select * into v_control from imagineos_private.illustration_control where singleton for update;
  select id into v_family from public.families where parent_user_id=p_parent_id for update;
  if v_family is null then raise exception 'Family unavailable'; end if;
  if p_request_id is null or p_trace_id is null or p_fingerprint is null or
      p_fingerprint !~ '^[0-9a-f]{64}$' or p_provider is null or p_provider not in ('openai','gemini') or
      p_max_cost_micros is null or p_max_cost_micros not between 1 and 1000000
    then raise exception 'Invalid request'; end if;
  select * into v_job from imagineos_private.illustration_jobs where family_id=v_family and request_id=p_request_id;
  if found then
    if v_job.fingerprint<>p_fingerprint or v_job.provider<>p_provider or
        v_job.source_id is distinct from p_source_id or v_job.max_cost_micros<>p_max_cost_micros then
      return jsonb_build_object('status','conflict');
    end if;
    return jsonb_build_object('status',v_job.state,'replay',true,'trace_id',v_job.trace_id);
  end if;
  if v_control.singleton is distinct from true or not coalesce(v_control.enabled,false)
    then return jsonb_build_object('status','disabled'); end if;
  if not exists(select 1 from public.original_assets a join public.character_versions v on v.id=a.version_id
      join public.characters c on c.id=v.character_id
      where a.id=p_source_id and a.family_id=v_family and a.state='ready'
      and not v.deletion_requested and not c.deletion_requested)
    then return jsonb_build_object('status','reference_unavailable'); end if;
  if not exists(select 1 from imagineos_private.provider_connections where family_id=v_family and provider=p_provider)
    then return jsonb_build_object('status','provider_unavailable'); end if;
  insert into imagineos_private.illustration_family_limits(family_id) values(v_family) on conflict do nothing;
  select * into v_limit from imagineos_private.illustration_family_limits where family_id=v_family for update;
  if v_limit.usage_day<>(now() at time zone 'utc')::date then
    update imagineos_private.illustration_family_limits set usage_day=(now() at time zone 'utc')::date,
      daily_attempts=0 where family_id=v_family;
    v_limit.daily_attempts:=0;
  end if;
  if v_limit.daily_attempts>=v_limit.daily_limit or
      v_limit.spent_micros+v_limit.reserved_micros+p_max_cost_micros>v_limit.authorized_micros or
      v_control.spent_micros+v_control.reserved_micros+p_max_cost_micros>v_control.authorized_micros then
    return jsonb_build_object('status','quota_exhausted');
  end if;
  insert into imagineos_private.illustration_jobs(family_id,request_id,trace_id,fingerprint,provider,source_id,max_cost_micros)
    values(v_family,p_request_id,p_trace_id,p_fingerprint,p_provider,p_source_id,p_max_cost_micros);
  update imagineos_private.illustration_control set reserved_micros=reserved_micros+p_max_cost_micros where singleton;
  update imagineos_private.illustration_family_limits set reserved_micros=reserved_micros+p_max_cost_micros,
    daily_attempts=daily_attempts+1 where family_id=v_family;
  return jsonb_build_object('status','reserved','replay',false,'trace_id',p_trace_id);
end;
$$;
revoke all on function imagineos_private.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint)
  from public,anon,authenticated;
grant execute on function imagineos_private.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint) to service_role;
create function public.reserve_illustration(
  p_parent_id uuid,p_session_id uuid,p_request_id uuid,p_trace_id uuid,
  p_fingerprint text,p_provider text,p_source_id uuid,p_max_cost_micros bigint
) returns jsonb language sql security invoker set search_path='' as $$
  select imagineos_private.reserve_illustration(p_parent_id,p_session_id,p_request_id,p_trace_id,
    p_fingerprint,p_provider,p_source_id,p_max_cost_micros);
$$;
revoke all on function public.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint) from public,anon,authenticated;
grant execute on function public.reserve_illustration(uuid,uuid,uuid,uuid,text,text,uuid,bigint) to service_role;

create function imagineos_private.advance_illustration(
  p_family_id uuid,p_request_id uuid,p_action text,p_actual_cost_micros bigint default null
) returns text language plpgsql security definer set search_path='' as $$
declare
  v_enabled boolean;
  v_job imagineos_private.illustration_jobs;
begin
  select enabled into v_enabled from imagineos_private.illustration_control where singleton for update;
  perform 1 from imagineos_private.illustration_family_limits where family_id=p_family_id for update;
  select * into v_job from imagineos_private.illustration_jobs where family_id=p_family_id and request_id=p_request_id for update;
  if not found then raise exception 'Job unavailable'; end if;
  if p_action='claim' then
    if not coalesce(v_enabled,false) then return 'disabled'; end if;
    if v_job.state<>'reserved' or v_job.attempts<>0 then return 'already_claimed'; end if;
    if not exists(select 1 from imagineos_private.provider_connections where family_id=p_family_id and provider=v_job.provider)
      then return 'provider_unavailable'; end if;
    if not exists(select 1 from public.original_assets where id=v_job.source_id and state='ready')
      then return 'reference_unavailable'; end if;
    update imagineos_private.illustration_jobs set state='running',attempts=1 where family_id=p_family_id and request_id=p_request_id;
    return 'running';
  end if;
  if p_action='indeterminate' then
    if v_job.state='running' then
      update imagineos_private.illustration_jobs set state='indeterminate' where family_id=p_family_id and request_id=p_request_id;
    end if;
    -- Timeout/unknown cost never releases its reservation or authorizes retry.
    if v_job.state in ('running','indeterminate') then return 'indeterminate'; end if;
    return v_job.state;
  end if;
  if p_action is null or p_action not in ('succeeded','rejected','failed') or
      p_actual_cost_micros is null or p_actual_cost_micros not between 0 and v_job.max_cost_micros then
    raise exception 'Invalid settlement';
  end if;
  if v_job.state in ('succeeded','rejected','failed') then
    if v_job.state<>p_action or v_job.actual_cost_micros<>p_actual_cost_micros then raise exception 'Settlement conflict'; end if;
    return v_job.state;
  end if;
  if v_job.state='reserved' and p_actual_cost_micros<>0 then raise exception 'Unclaimed job cannot have cost'; end if;
  if v_job.state='reserved' and p_action='succeeded' then raise exception 'Unclaimed job cannot succeed'; end if;
  update imagineos_private.illustration_jobs set state=p_action,actual_cost_micros=p_actual_cost_micros
    where family_id=p_family_id and request_id=p_request_id;
  update imagineos_private.illustration_control set reserved_micros=reserved_micros-v_job.max_cost_micros,
    spent_micros=spent_micros+p_actual_cost_micros where singleton;
  update imagineos_private.illustration_family_limits set reserved_micros=reserved_micros-v_job.max_cost_micros,
    spent_micros=spent_micros+p_actual_cost_micros where family_id=p_family_id;
  return p_action;
end;
$$;
revoke all on function imagineos_private.advance_illustration(uuid,uuid,text,bigint) from public,anon,authenticated;
grant execute on function imagineos_private.advance_illustration(uuid,uuid,text,bigint) to service_role;
create function public.advance_illustration(p_family_id uuid,p_request_id uuid,p_action text,p_actual_cost_micros bigint default null)
returns text language sql security invoker set search_path='' as $$
  select imagineos_private.advance_illustration(p_family_id,p_request_id,p_action,p_actual_cost_micros);
$$;
revoke all on function public.advance_illustration(uuid,uuid,text,bigint) from public,anon,authenticated;
grant execute on function public.advance_illustration(uuid,uuid,text,bigint) to service_role;
