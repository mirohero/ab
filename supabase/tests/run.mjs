// Isolated PostgreSQL-compatible test database. Never connects to Supabase.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const user1='11111111-1111-4111-8111-111111111111';
const user2='22222222-2222-4222-8222-222222222222';
let seq=0;
const request=()=>`00000000-0000-4000-8000-${String(++seq).padStart(12,'0')}`;
const call=async(action,run=null,question=null,option=null,id=request())=> {
 const result=await db.query('select public.study_call($1::uuid,$2,$3::uuid,$4,$5) as result',[id,action,run,question,option]);
 return result.rows[0].result;
};
const user=async(id)=> db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
await db.exec(`
 create role anon; create role authenticated;
 create schema auth;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 insert into auth.users values('${user1}'),('${user2}');
 grant usage on schema auth to anon,authenticated;
 grant execute on function auth.uid() to anon,authenticated;
`);
await db.exec(readFileSync(new URL('../migrations/002_research.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../003_seed.sql',import.meta.url),'utf8'));
await user(user1);
await db.exec('set role authenticated');
const visitRequest=request();
const visit=await call('visit',null,null,null,visitRequest);
assert.equal(visit.ok,true);
assert.equal(visit.data.questions.length,3);
assert.equal('rules' in visit.data,false);
const run=visit.data.run_id;
assert.deepEqual(await call('visit',null,null,null,visitRequest),visit);
assert.equal((await call('finish',run)).error,'INCOMPLETE_ANSWERS');
assert.equal((await call('selection',run,'urgency','urgent')).error,'PREVIOUS_QUESTION_MISSING');
assert.equal((await call('selection',run,'topic','forged')).error,'INVALID_OPTION');
const choose=request();
assert.equal((await call('selection',run,'topic','software',choose)).ok,true);
assert.equal((await call('selection',run,'topic','software',choose)).ok,true);
assert.equal((await call('selection',run,'topic','hardware',choose)).error,'REQUEST_ID_REUSED');
assert.equal((await call('selection',run,'topic','hardware')).ok,true);
assert.equal((await call('selection',run,'urgency','urgent')).ok,true);
assert.equal((await call('selection',run,'people','many')).ok,true);
const finishRequest=request();
const finish=await call('finish',run,null,null,finishRequest);
assert.equal(finish.data.result.id,'high');
assert.deepEqual(await call('finish',run,null,null,finishRequest),finish);
assert.equal((await call('selection',run,'people','one')).error,'RUN_ALREADY_COMPLETE');
for (const sql of [
 'select * from public.study_events',
 "update public.study_runs set answers='{}'",
 'delete from public.study_counters',
 "select study_private.take_limit('x',999)",
]) { await assert.rejects(db.query(sql),/permission denied/); }
await user(user2);
assert.equal((await call('selection',run,'topic','software')).error,'RUN_NOT_FOUND');
await db.exec('reset role');
const rows=(await db.query('select * from public.study_events order by id')).rows;
assert.equal(rows.length,6); // visit, 4 selections, result: retries not duplicated
assert.deepEqual(rows.map(r=>r.sequence),[1,2,3,4,5,6]);
assert.ok(rows.every(r=>r.recorded_at));
const sums=(await db.query("select sum(event_count) as count, sum(numeric_sum) as sum from public.study_counters")).rows[0];
assert.equal(Number(sums.count),6);
assert.equal(Number(sums.sum),7); // software1 + hardware2 + urgent1 + many2 + result1
await assert.rejects(db.query("update public.study_versions set definition=jsonb_set(definition,'{questions,0,title}','\"changed\"')"),/immutable/);
await db.exec('set role authenticated');
await user(user1);
// Existing attempts consume the same budget as duplicate/invalid calls.
let limited=false;
for(let i=0;i<61;i++) { const r=await call('visit'); if(r.error==='RATE_LIMIT') {limited=true;break;} }
assert.equal(limited,true);
await db.exec('reset role');
await db.query("update study_private.limits set calls=1000 where key='global'");
await db.exec('set role authenticated');
await user(user2);
assert.equal((await call('visit')).error,'RATE_LIMIT');
await db.exec('reset role');
await db.exec(readFileSync(new URL('../reset_before_release.sql',import.meta.url),'utf8'));
assert.equal(Number((await db.query('select count(*) as n from public.study_events')).rows[0].n),0);
assert.equal(Number((await db.query('select count(*) as n from public.study_counters')).rows[0].n),0);
assert.equal(Number((await db.query('select count(*) as n from public.study_runs')).rows[0].n),0);
assert.equal(Number((await db.query('select count(*) as n from study_private.requests')).rows[0].n),0);
assert.equal(Number((await db.query('select count(*) as n from public.study_versions')).rows[0].n),1);
await db.exec('set role anon');
await assert.rejects(call('visit'),/permission denied/);
await db.exec('reset role');
await user('');
await db.exec('set role authenticated');
await assert.rejects(call('visit'),/AUTH_REQUIRED/);
await db.close();
console.log('PASS: server config, rule evaluation, events/sums, idempotency, ownership, grants, rate limits, reset');
