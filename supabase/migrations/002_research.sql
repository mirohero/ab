begin;
create schema if not exists study_private;
revoke all on schema study_private from public, anon, authenticated;

create table public.study_versions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  published boolean not null default false,
  definition jsonb not null,
  created_at timestamptz not null default now()
);
create unique index study_one_published on public.study_versions ((published)) where published;
create table public.study_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  version_id uuid not null references public.study_versions(id),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  answers jsonb not null default '{}',
  result jsonb,
  event_count integer not null default 0
);
create table public.study_events (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.study_runs(id) on delete cascade,
  version_id uuid not null references public.study_versions(id),
  user_id uuid not null references auth.users(id),
  request_id uuid not null,
  sequence integer not null,
  recorded_at timestamptz not null default clock_timestamp(),
  kind text not null check (kind in ('visit','selection','result')),
  question_id text not null default '',
  option_id text not null default '',
  result_id text not null default '',
  numeric_code integer,
  snapshot jsonb not null,
  unique(run_id,sequence), unique(user_id,request_id)
);
create index study_events_time on public.study_events(recorded_at,id);
create table public.study_counters (
  version_id uuid not null references public.study_versions(id),
  kind text not null,
  question_id text not null default '',
  item_id text not null default '',
  event_count bigint not null default 0,
  numeric_sum bigint not null default 0,
  primary key(version_id,kind,question_id,item_id)
);
create table study_private.requests (
  user_id uuid not null,
  request_id uuid not null,
  signature jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(user_id,request_id)
);
create table study_private.limits (
  key text primary key,
  window_start timestamptz not null,
  calls integer not null
);

-- No direct browser access, even with authenticated users. Only study_call is exposed.
alter table public.study_versions enable row level security;
alter table public.study_runs enable row level security;
alter table public.study_events enable row level security;
alter table public.study_counters enable row level security;
revoke all on public.study_versions, public.study_runs, public.study_events,
  public.study_counters from public, anon, authenticated;
revoke all on sequence public.study_events_id_seq from public, anon, authenticated;

-- Freeze definitions after first use; publish a new version instead of rewriting history.
create function study_private.validate_version() returns trigger
language plpgsql set search_path = '' as $$
declare q jsonb; o jsonb; rule jsonb; key text; val jsonb;
begin
  if TG_OP = 'UPDATE' and new.definition is distinct from old.definition
    and exists(select 1 from public.study_runs where version_id=old.id) then
    raise exception 'Used definition is immutable; create a new version';
  end if;
  if jsonb_typeof(new.definition->'questions') is distinct from 'array'
    or jsonb_typeof(new.definition->'rules') is distinct from 'array' then
    raise exception 'questions and rules must be arrays';
  end if;
  if jsonb_array_length(new.definition->'questions') not between 1 and 50
    or jsonb_array_length(new.definition->'rules') not between 1 and 100 then
    raise exception 'Invalid definition size';
  end if;
  if (select count(distinct v->>'id') from jsonb_array_elements(new.definition->'questions') v)
    <> jsonb_array_length(new.definition->'questions') then raise exception 'Duplicate question IDs'; end if;
  for q in select value from jsonb_array_elements(new.definition->'questions') loop
    if coalesce(length(q->>'id'),0) not between 1 and 80 or coalesce(length(q->>'title'),0)=0
      or jsonb_typeof(q->'options') is distinct from 'array' then raise exception 'Invalid question'; end if;
    if jsonb_array_length(q->'options') not between 2 and 20 then raise exception 'Invalid options'; end if;
    if (select count(distinct v->>'id') from jsonb_array_elements(q->'options') v)
      <> jsonb_array_length(q->'options') then raise exception 'Duplicate option IDs'; end if;
    for o in select value from jsonb_array_elements(q->'options') loop
      if coalesce(length(o->>'id'),0) not between 1 and 80 or coalesce(length(o->>'label'),0)=0
        or jsonb_typeof(o->'code') is distinct from 'number' then raise exception 'Invalid option'; end if;
      perform (o->>'code')::integer;
    end loop;
  end loop;
  if (select count(distinct v->>'id') from jsonb_array_elements(new.definition->'rules') v)
    <> jsonb_array_length(new.definition->'rules') then raise exception 'Duplicate result IDs'; end if;
  for rule in select value from jsonb_array_elements(new.definition->'rules') loop
    if coalesce(length(rule->>'id'),0) not between 1 and 80 or coalesce(length(rule->>'title'),0)=0
      or coalesce(length(rule->>'text'),0)=0 or jsonb_typeof(rule->'when') is distinct from 'object'
      or jsonb_typeof(rule->'code') is distinct from 'number' then raise exception 'Invalid rule'; end if;
    perform (rule->>'code')::integer;
    for key,val in select * from jsonb_each(rule->'when') loop
      if not exists(select 1 from jsonb_array_elements(new.definition->'questions') qq,
        lateral jsonb_array_elements(qq->'options') oo where qq->>'id'=key and oo->>'id'=val#>>'{}')
        then raise exception 'Rule references unknown selection'; end if;
    end loop;
  end loop;
  if not exists(select 1 from jsonb_array_elements(new.definition->'rules') r where r->'when'='{}'::jsonb)
    then raise exception 'A fallback rule is required'; end if;
  return new;
end $$;
create trigger validate_study_version before insert or update on public.study_versions
for each row execute function study_private.validate_version();

create function study_private.count_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.study_counters(version_id,kind,question_id,item_id,event_count,numeric_sum)
  values(new.version_id,new.kind,new.question_id,
    case when new.kind='selection' then new.option_id else new.result_id end,1,coalesce(new.numeric_code,0))
  on conflict(version_id,kind,question_id,item_id) do update set
    event_count=public.study_counters.event_count+1,
    numeric_sum=public.study_counters.numeric_sum+excluded.numeric_sum;
  return new;
end $$;
create trigger count_study_event after insert on public.study_events
for each row execute function study_private.count_event();

create function study_private.take_limit(p_key text,p_max integer) returns boolean
language plpgsql set search_path = '' as $$
declare n integer; t timestamptz := clock_timestamp();
begin
  insert into study_private.limits(key,window_start,calls) values(p_key,t,1)
  on conflict(key) do update set
    calls=case when study_private.limits.window_start <= t-interval '60 seconds' then 1 else study_private.limits.calls+1 end,
    window_start=case when study_private.limits.window_start <= t-interval '60 seconds' then t else study_private.limits.window_start end
  returning calls into n;
  return n <= p_max;
end $$;

create function study_private.process(p_user uuid,p_request uuid,p_action text,
 p_run uuid,p_question text,p_option text) returns jsonb
language plpgsql set search_path = '' as $$
declare r public.study_runs%rowtype; v public.study_versions%rowtype;
 q jsonb; o jsonb; rule jsonb; outcome jsonb; n integer;
begin
  if p_action='visit' then
    select * into v from public.study_versions where published;
    if not found then raise exception 'NO_PUBLISHED_STUDY'; end if;
    insert into public.study_runs(user_id,version_id) values(p_user,v.id) returning * into r;
    insert into public.study_events(run_id,version_id,user_id,request_id,sequence,kind,snapshot)
      values(r.id,v.id,p_user,p_request,1,'visit',jsonb_build_object('title',v.title));
    update public.study_runs set event_count=1 where id=r.id;
    return jsonb_build_object('run_id',r.id,'version_id',v.id,'started_at',r.started_at,
      'title',v.title,'questions',v.definition->'questions');
  end if;
  select * into r from public.study_runs where id=p_run and user_id=p_user for update;
  if not found then raise exception 'RUN_NOT_FOUND'; end if;
  if r.completed_at is not null then raise exception 'RUN_ALREADY_COMPLETE'; end if;
  if r.event_count >= 200 then raise exception 'RUN_EVENT_LIMIT'; end if;
  select * into v from public.study_versions where id=r.version_id;
  if p_action='selection' then
    select value into q from jsonb_array_elements(v.definition->'questions') where value->>'id'=p_question;
    if q is null then raise exception 'INVALID_QUESTION'; end if;
    select value into o from jsonb_array_elements(q->'options') where value->>'id'=p_option;
    if o is null then raise exception 'INVALID_OPTION'; end if;
    -- All preceding questions must have an answer.
    for rule in select value from jsonb_array_elements(v.definition->'questions') loop
      exit when rule->>'id'=p_question;
      if not r.answers ? (rule->>'id') then raise exception 'PREVIOUS_QUESTION_MISSING'; end if;
    end loop;
    r.answers := jsonb_set(r.answers,array[p_question],to_jsonb(p_option),true);
    n:=r.event_count+1;
    insert into public.study_events(run_id,version_id,user_id,request_id,sequence,kind,question_id,option_id,numeric_code,snapshot)
      values(r.id,v.id,p_user,p_request,n,'selection',p_question,p_option,(o->>'code')::integer,
        jsonb_build_object('question',q->>'title','option',o->>'label','answers',r.answers));
    update public.study_runs set answers=r.answers,event_count=n where id=r.id;
    return jsonb_build_object('answers',r.answers,'sequence',n);
  elsif p_action='finish' then
    for q in select value from jsonb_array_elements(v.definition->'questions') loop
      if not r.answers ? (q->>'id') then raise exception 'INCOMPLETE_ANSWERS'; end if;
    end loop;
    for rule in select value from jsonb_array_elements(v.definition->'rules') loop
      if r.answers @> (rule->'when') then
        outcome := rule - 'when'; exit;
      end if;
    end loop;
    if outcome is null then raise exception 'NO_MATCHING_RULE'; end if;
    n:=r.event_count+1;
    insert into public.study_events(run_id,version_id,user_id,request_id,sequence,kind,result_id,numeric_code,snapshot)
      values(r.id,v.id,p_user,p_request,n,'result',outcome->>'id',(outcome->>'code')::integer,
        jsonb_build_object('result',outcome,'answers',r.answers));
    update public.study_runs set result=outcome,completed_at=clock_timestamp(),event_count=n where id=r.id;
    return jsonb_build_object('result',outcome,'sequence',n);
  end if;
  raise exception 'INVALID_ACTION';
end $$;

create function public.study_call(p_request uuid,p_action text,p_run uuid default null,
 p_question text default null,p_option text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); response jsonb; sig jsonb; previous study_private.requests%rowtype;
 user_ok boolean; global_ok boolean;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  -- Shared locks let admin reset wait for in-flight writes, then reset atomically.
  perform pg_advisory_xact_lock_shared(820026);
  perform pg_advisory_xact_lock(hashtextextended(u::text,820027));
  user_ok:=study_private.take_limit('user:'||u::text,60);
  global_ok:=study_private.take_limit('global',1000);
  if not user_ok or not global_ok then
    return jsonb_build_object('ok',false,'error','RATE_LIMIT','retry_after',60);
  end if;
  if p_request is null or p_action not in ('visit','selection','finish') or p_action is null
    or coalesce(length(p_question),0)>80 or coalesce(length(p_option),0)>80 then
    return jsonb_build_object('ok',false,'error','INVALID_INPUT');
  end if;
  sig:=jsonb_build_object('action',p_action,'run',p_run,'question',p_question,'option',p_option);
  select * into previous from study_private.requests where user_id=u and request_id=p_request;
  if found then
    if previous.signature<>sig then return jsonb_build_object('ok',false,'error','REQUEST_ID_REUSED'); end if;
    return previous.response;
  end if;
  begin
    response:=jsonb_build_object('ok',true,'data',study_private.process(u,p_request,p_action,p_run,p_question,p_option));
  exception when raise_exception then
    response:=jsonb_build_object('ok',false,'error',SQLERRM);
  end;
  -- Retain successful responses indefinitely to avoid duplicate research events on retry.
  if response->>'ok'='true' then
    insert into study_private.requests(user_id,request_id,signature,response) values(u,p_request,sig,response);
  end if;
  return response;
end $$;
revoke all on function public.study_call(uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.study_call(uuid,text,uuid,text,text) to authenticated;
revoke all on all functions in schema study_private from public,anon,authenticated;

-- Block v1 write/read path without deleting existing v1 data.
do $$ begin
 if to_regclass('public.questionnaire_sessions') is not null then
  revoke all on public.questionnaire_sessions from anon,authenticated;
 end if;
end $$;
commit;
