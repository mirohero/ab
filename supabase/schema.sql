-- Im Supabase SQL Editor ausführen. Für eine neue Tabelle vorgesehen.
begin;
create table if not exists public.questionnaire_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  started_at timestamptz not null,
  completed_at timestamptz,
  answers jsonb not null default '{}'::jsonb,
  decision jsonb,
  primary key (user_id, id),
  constraint answers_object check (jsonb_typeof(answers) = 'object'),
  constraint valid_completion check (
    (completed_at is null and decision is null) or
    (completed_at is not null and completed_at >= started_at
      and decision is not null and jsonb_typeof(decision) = 'object')
  )
);
alter table public.questionnaire_sessions enable row level security;
revoke all on public.questionnaire_sessions from anon, authenticated;
grant select, insert, update, delete on public.questionnaire_sessions to authenticated;

drop policy if exists sessions_select_own on public.questionnaire_sessions;
create policy sessions_select_own on public.questionnaire_sessions
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists sessions_insert_own on public.questionnaire_sessions;
create policy sessions_insert_own on public.questionnaire_sessions
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists sessions_update_own on public.questionnaire_sessions;
create policy sessions_update_own on public.questionnaire_sessions
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists sessions_delete_own on public.questionnaire_sessions;
create policy sessions_delete_own on public.questionnaire_sessions
  for delete to authenticated using ((select auth.uid()) = user_id);
commit;

-- Optional: Nutzungsübersicht nur im SQL Editor (kein öffentlicher API-Endpunkt).
-- select count(*) as gestartet,
--   count(completed_at) as abgeschlossen,
--   count(*) - count(completed_at) as offen
-- from public.questionnaire_sessions;
