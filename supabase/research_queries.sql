-- Nur im SQL Editor als Projektbetreiber: kein öffentlicher Admin-Endpunkt.
-- Zeitlicher Rohdatenexport (CSV über Dashboard/SQL-Resultat).
select e.id,e.recorded_at,e.run_id,e.user_id,e.version_id,e.sequence,e.kind,
       e.question_id,e.option_id,e.result_id,e.numeric_code,e.snapshot
from public.study_events e order by e.recorded_at,e.id;

-- Laufende Summen/Häufigkeiten pro Version/Frage/Option/Ergebnis.
select * from public.study_counters order by version_id,kind,question_id,item_id;

-- Finale Antworten: Auswahlwechsel werden hier nicht mehrfach gezählt.
select r.version_id,a.key as question_id,a.value as option_id,count(*) as completed_runs
from public.study_runs r cross join lateral jsonb_each_text(r.answers) a
where r.completed_at is not null group by r.version_id,a.key,a.value;

-- Ergebnisverteilung und Bearbeitungsdauer.
select version_id,result->>'id' as result_id,count(*) as count,
 avg(extract(epoch from (completed_at-started_at))) as average_seconds
from public.study_runs where completed_at is not null group by version_id,result->>'id';

-- Zählerkonsistenz: muss null Zeilen liefern (nach jedem Setup/Reset prüfen).
with actual as (
 select version_id,kind,question_id,
 case when kind='selection' then option_id else result_id end as item_id,
 count(*) as event_count,sum(coalesce(numeric_code,0)) as numeric_sum
 from public.study_events group by 1,2,3,4
)
select * from actual a full join public.study_counters c using(version_id,kind,question_id,item_id)
where a.event_count is distinct from c.event_count or a.numeric_sum is distinct from c.numeric_sum;
