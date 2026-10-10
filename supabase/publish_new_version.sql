-- JSON-Konfiguration einer neuen Version ersetzen und als Ganzes ausführen.
-- Bereits benutzte Definitionen dürfen nicht geändert werden.
begin;
update public.study_versions set published=false where published;
insert into public.study_versions(title,published,definition)
values ('Mein Fragebogen',true,$definition$
{
 "questions":[
   {"id":"q1","title":"Welche Auswahl trifft zu?","options":[
     {"id":"a","label":"Option A","code":1},
     {"id":"b","label":"Option B","code":2}
   ]}
 ],
 "rules":[
   {"id":"r1","code":1,"when":{"q1":"a"},"title":"Ergebnis A","text":"Deine Antwort für A."},
   {"id":"r2","code":2,"when":{},"title":"Ergebnis B","text":"Deine Standardantwort."}
 ]
}
$definition$::jsonb);
commit;
