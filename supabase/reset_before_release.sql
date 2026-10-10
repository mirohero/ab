-- DESTRUKTIV: erst CSV-Export/Backup erstellen. Nur manuell im SQL Editor ausführen.
-- Kein Reset-Endpunkt in der Webapp. Fragebogen-Konfiguration bleibt erhalten.
-- Angehaltene/ältere Browserdurchläufe danach neu laden.
begin;
select pg_advisory_xact_lock(820026);
truncate table public.study_events, public.study_runs, public.study_counters,
 study_private.requests, study_private.limits restart identity;
-- Entfernt auch die Testdaten aus der vorherigen App-Version, falls vorhanden.
do $$ begin
 if to_regclass('public.questionnaire_sessions') is not null then
   truncate table public.questionnaire_sessions;
 end if;
end $$;
commit;
-- auth.users bleiben erhalten: aktive anonyme Sitzungen funktionieren weiter.
-- Fremde Auth-Benutzer/andere Projektanwendungen werden nicht gelöscht.
