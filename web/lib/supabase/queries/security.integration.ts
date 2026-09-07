import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import { setTimeout } from "node:timers/promises";
import postgres from "postgres";
import { deleteAccount } from "./delete-account-supabase-query";
import { declineMembership } from "./decline-membership-supabase-query";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";
import { saveHealthKitDiagnosticSnapshot } from "./healthkit-diagnostics-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";
import { healthKitDiagnosticSnapshotSchema } from "@/lib/types/healthkit/healthkit-diagnostic";

const databaseURL = process.env.DATABASE_URL;
if (process.env.CI !== "true" || !databaseURL
  || !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)) {
  throw new Error("These tests require the disposable local database in cloud CI");
}
process.env.NEXT_PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
process.env.SUPABASE_SECRET_KEY = "test-only-unused-storage-client";
const database = postgres(databaseURL, {
  max: 4,
  connection: { application_name: "fitfight-security-tests" },
});
after(() => database.end());

async function fixture(t: TestContext) {
  const users = [randomUUID(), randomUUID()].sort();
  const owner = users[0];
  const peer = users[1];
  const fightId = randomUUID();
  const sourceIds = [randomUUID(), randomUUID()];
  const now = new Date();
  const endsAt = new Date(now.getTime() - 3_600_000).toISOString();
  const startsAt = new Date(Date.parse(endsAt) - 3 * 86_400_000).toISOString();
  t.after(async () => {
    await database`delete from public.fights where owner_id = any(${database.array(users)}::uuid[])`;
    await database`delete from public.fight_series where owner_id = any(${database.array(users)}::uuid[])`;
    await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
  });
  for (const [index, userId] of users.entries()) {
    await database`insert into auth.users (id) values (${userId})`;
    await database`
      insert into public.data_sources (id, user_id, provider, source_label, connection_route)
      values (${sourceIds[index]}, ${userId}, 'apple_health', 'Apple Health', 'healthkit')
    `;
  }
  await database`
    insert into public.fights (
      id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
    ) values (${fightId}, ${owner}, 'Security test', 'live', ${startsAt}, ${endsAt},
      'UTC', 'highest_total', 'shared')
  `;
  for (const [index, userId] of users.entries()) {
    await database`
      insert into public.fight_members (fight_id, user_id, state, selected_source_id)
      values (${fightId}, ${userId}, 'accepted', ${sourceIds[index]})
    `;
  }
  return { users, owner, peer, fightId, sourceIds, now, endsAt, startsAt };
}

test("diagnostic reports persist JSON timing arrays once per user and attempt", async (t) => {
  const f = await fixture(t);
  const input = healthKitDiagnosticSnapshotSchema.parse({
    background_refresh_status: "available",
    delivery_registration_status: "enabled",
    app_version: "1.0.0",
    app_build: "42",
    attempts: [{
      attempt_id: randomUUID(), trigger: "foreground", started_at: f.now.toISOString(),
      outcome: "succeeded", total_ms: 125.5,
      stages: [{
        stage: "upload", started_ms: 20, duration_ms: 100.5, outcome: "succeeded",
        server_timing: { db_ms: 25.5 },
      }],
    }],
  });
  const result = await saveHealthKitDiagnosticSnapshot(f.owner, input, database);
  assert.ok(Number.isFinite(Date.parse(result.updated_at)));
  await saveHealthKitDiagnosticSnapshot(f.owner, input, database);
  const rows = await database`
    select user_id, total_ms, stages from private.healthkit_sync_attempts
    where user_id = any(${database.array(f.users)}::uuid[])
  `;
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0], {
    user_id: f.owner, total_ms: 125.5, stages: input.attempts?.[0].stages,
  });
});

test("a source watermark cannot finalize a fight without exact end snapshots", async (t) => {
  const f = await fixture(t);
  const cutoff = new Date(Date.parse(f.endsAt) - 60_000).toISOString();
  await syncHealthKitAggregates(f.owner, {
    complete_through: cutoff, time_zone: "UTC", merged_days: [],
    fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt,
      ends_at: f.endsAt, cutoff_at: cutoff, steps: 42 }],
  }, database);
  await database`
    update public.data_sources set complete_through = ${f.now.toISOString()}
    where user_id = any(${database.array(f.users)}::uuid[])
  `;
  await recalculateFight(f.fightId, f.now, database);
  const [pending] = await database`select state from public.fights where id = ${f.fightId}`;
  assert.equal(pending.state, "awaiting_final_sync");
  const pendingMembers = await database`
    select final_steps_complete, final_value from public.fight_members where fight_id = ${f.fightId}
  `;
  assert.ok(pendingMembers.every((row) => !row.final_steps_complete && row.final_value === null));
  await recalculateFight(f.fightId, new Date(Date.parse(f.endsAt) + 86_400_001), database);
  const finalized = await database`
    select user_id, final_value::text, final_steps_complete, finalized_at
    from public.fight_members where fight_id = ${f.fightId} order by user_id
  `;
  assert.deepEqual(finalized.map((row) => row.final_value), ["42", "0"]);
  assert.ok(finalized.every((row) => !row.final_steps_complete && row.finalized_at !== null));
});

test("latest selected-source exact snapshots freeze together and reject later uploads", async (t) => {
  const f = await fixture(t);
  const readings = [[f.owner, 10], [f.owner, 20], [f.owner, 10], [f.peer, 30]] as const;
  for (const [index, [userId, steps]] of readings.entries()) {
    await syncHealthKitAggregates(userId, {
      complete_through: new Date(f.now.getTime() - 1000 + index).toISOString(), time_zone: "UTC", merged_days: [],
      fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt,
        ends_at: f.endsAt, cutoff_at: f.endsAt, steps }],
    }, database);
  }
  const unrelatedSource = randomUUID();
  await database`
    insert into public.data_sources (id, user_id, provider, source_label, connection_route)
    values (${unrelatedSource}, ${f.owner}, 'apple_health', 'Unselected', 'legacy')
  `;
  await database`
    insert into private.fight_score_snapshots (
      fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
    ) values (${f.fightId}, ${f.owner}, ${unrelatedSource}, ${f.endsAt}, 999999, repeat('f', 64), 1)
  `;
  await recalculateFight(f.fightId, f.now, database);
  const before = await database`
    select * from public.fight_members where fight_id = ${f.fightId} order by user_id
  `;
  assert.deepEqual(before.map((row) => row.final_value), ["10", "30"]);
  assert.deepEqual(before.map((row) => row.rank), [2, 1]);
  assert.ok(before.every((row) => row.final_steps_complete && row.finalized_at !== null));
  const frozen = await database`
    select value::text from private.fight_score_snapshots
    where fight_id = ${f.fightId} and is_final order by user_id
  `;
  assert.deepEqual(frozen.map((row) => row.value), ["10", "30"]);
  await assert.rejects(syncHealthKitAggregates(f.owner, {
    complete_through: f.now.toISOString(), time_zone: "UTC", merged_days: [],
    fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt,
      ends_at: f.endsAt, cutoff_at: f.endsAt, steps: 99 }],
  }, database), /does not match sync context/);
  await recalculateFight(f.fightId, new Date(f.now.getTime() + 86_400_000), database);
  const after = await database`
    select * from public.fight_members where fight_id = ${f.fightId} order by user_id
  `;
  assert.deepEqual(after, before);
});

test("batched uploads preserve independent fight scores, corrections, replay, and overlapping rosters", async (t) => {
  const f = await fixture(t);
  const secondFightId = randomUUID();
  const secondEndsAt = new Date(f.now.getTime() + 3_600_000).toISOString();
  await database`
    insert into public.fights (
      id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
    ) values (${secondFightId}, ${f.owner}, 'Second batch fight', 'live', ${f.startsAt},
      ${secondEndsAt}, 'UTC', 'highest_total', 'shared')
  `;
  for (const [index, userId] of f.users.entries()) {
    await database`
      insert into public.fight_members (fight_id, user_id, state, selected_source_id)
      values (${secondFightId}, ${userId}, 'accepted', ${f.sourceIds[index]})
    `;
  }
  const ownerReadings = [[10, 90], [20, 30], [10, 90]];
  for (const [index, [firstSteps, secondSteps]] of ownerReadings.entries()) {
    const checkpoint = new Date(f.now.getTime() - 1000 + index).toISOString();
    await syncHealthKitAggregates(f.owner, {
      complete_through: checkpoint, time_zone: "UTC", merged_days: [],
      fight_aggregates: [
        { fight_id: secondFightId, starts_at: f.startsAt, ends_at: secondEndsAt,
          cutoff_at: checkpoint, steps: secondSteps },
        { fight_id: f.fightId, starts_at: f.startsAt, ends_at: f.endsAt,
          cutoff_at: f.endsAt, steps: firstSteps },
      ],
    }, database);
  }
  const replayCheckpoint = new Date(f.now.getTime() - 998).toISOString();
  await Promise.all([
    syncHealthKitAggregates(f.owner, {
      complete_through: replayCheckpoint, time_zone: "UTC", merged_days: [],
      fight_aggregates: [
        { fight_id: secondFightId, starts_at: f.startsAt, ends_at: secondEndsAt,
          cutoff_at: replayCheckpoint, steps: 90 },
        { fight_id: f.fightId, starts_at: f.startsAt, ends_at: f.endsAt,
          cutoff_at: f.endsAt, steps: 10 },
      ],
    }, database),
    syncHealthKitAggregates(f.peer, {
      complete_through: f.now.toISOString(), time_zone: "UTC", merged_days: [],
      fight_aggregates: [
        { fight_id: f.fightId, starts_at: f.startsAt, ends_at: f.endsAt,
          cutoff_at: f.endsAt, steps: 15 },
        { fight_id: secondFightId, starts_at: f.startsAt, ends_at: secondEndsAt,
          cutoff_at: f.now.toISOString(), steps: 50 },
      ],
    }, database),
  ]);
  const firstMembers = await database`
    select current_value::text, rank, final_steps_complete, final_value
    from public.fight_members where fight_id = ${f.fightId} order by user_id
  `;
  assert.deepEqual(Array.from(firstMembers), [
    { current_value: "10", rank: 2, final_steps_complete: true, final_value: null },
    { current_value: "15", rank: 1, final_steps_complete: true, final_value: null },
  ]);
  const secondMembers = await database`
    select current_value::text, rank, final_steps_complete, final_value
    from public.fight_members where fight_id = ${secondFightId} order by user_id
  `;
  assert.deepEqual(Array.from(secondMembers), [
    { current_value: "90", rank: 1, final_steps_complete: false, final_value: null },
    { current_value: "50", rank: 2, final_steps_complete: false, final_value: null },
  ]);
  const snapshots = await database`
    select fight_id, count(*)::integer as count from private.fight_score_snapshots
    where user_id = ${f.owner} group by fight_id
  `;
  assert.equal(snapshots.length, 2);
  assert.ok(snapshots.every((row) => row.count === 3), "replay must not create another snapshot");
});

test("a failed bulk rank update rolls back the entire Apple Health upload", async (t) => {
  const f = await fixture(t);
  const completeThrough = f.now.toISOString();
  const day = f.startsAt.slice(0, 10);
  const dayStart = `${day}T00:00:00.000Z`;
  const dayEnd = new Date(Date.parse(dayStart) + 86_400_000).toISOString();
  await database`
    alter table public.fight_members add constraint security_test_aggregate_failure
    check (rank is distinct from 1)
  `;
  try {
    await assert.rejects(syncHealthKitAggregates(f.owner, {
      complete_through: completeThrough, time_zone: "UTC",
      merged_days: [{ day, starts_at: dayStart, ends_at: dayEnd, steps: 81 }],
      fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt,
        ends_at: f.endsAt, cutoff_at: f.endsAt, steps: 81 }],
    }, database), /security_test_aggregate_failure/);
    const members = await database`
      select current_value, rank, final_steps_complete from public.fight_members
      where fight_id = ${f.fightId}
    `;
    assert.ok(members.every((row) => row.current_value === null && row.rank === null && !row.final_steps_complete));
    const [source] = await database`
      select complete_through from public.data_sources where id = ${f.sourceIds[0]}
    `;
    assert.equal(source.complete_through, null);
    assert.equal((await database`
      select id from private.fight_score_snapshots where fight_id = ${f.fightId}
    `).length, 0);
    assert.equal((await database`
      select day from public.metric_days where user_id = ${f.owner}
    `).length, 0);
    assert.equal((await database`
      select day from public.step_days where user_id = ${f.owner}
    `).length, 0);
  } finally {
    await database`alter table public.fight_members drop constraint security_test_aggregate_failure`;
  }
});

test("finalization waits for an in-flight score transaction and reads its committed snapshot", async (t) => {
  const f = await fixture(t);
  let finalization = Promise.resolve();
  await database.begin(async (sql) => {
    await sql`select id from public.fights where id = ${f.fightId} for update`;
    finalization = recalculateFight(f.fightId, new Date(Date.parse(f.endsAt) + 86_400_001), database);
    let waiting = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const [activity] = await database`
        select exists (
          select 1 from pg_stat_activity
          where application_name = 'fitfight-security-tests' and wait_event_type = 'Lock'
        ) as waiting
      `;
      if (activity.waiting) { waiting = true; break; }
      await setTimeout(10);
    }
    assert.equal(waiting, true, "finalizer must wait for the fight lock");
    await sql`
      insert into private.fight_score_snapshots (
        fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
      ) values (${f.fightId}, ${f.owner}, ${f.sourceIds[0]}, ${f.endsAt}, 81, repeat('a', 64), 1)
    `;
  });
  await finalization;
  const [member] = await database`
    select final_value::text, final_steps_complete from public.fight_members
    where fight_id = ${f.fightId} and user_id = ${f.owner}
  `;
  assert.equal(member.final_value, "81");
  assert.equal(member.final_steps_complete, true);
});

test("a failure midway through finalization rolls back all scores and the fight state", async (t) => {
  const f = await fixture(t);
  for (const [index, userId] of f.users.entries()) {
    await database`
      insert into private.fight_score_snapshots (
        fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
      ) values (${f.fightId}, ${userId}, ${f.sourceIds[index]}, ${f.endsAt},
        ${(index + 1) * 10}, repeat('b', 64), 1)
    `;
  }
  await database`
    alter table public.fight_members add constraint security_test_finalization_failure
    check (final_value is distinct from 10)
  `;
  try {
    await assert.rejects(recalculateFight(f.fightId, f.now, database), /security_test_finalization_failure/);
    const [fight] = await database`select state from public.fights where id = ${f.fightId}`;
    assert.equal(fight.state, "live");
    const members = await database`
      select current_value, final_value, finalized_at from public.fight_members where fight_id = ${f.fightId}
    `;
    assert.ok(members.every((row) => row.current_value === null && row.final_value === null && row.finalized_at === null));
    const marked = await database`
      select id from private.fight_score_snapshots where fight_id = ${f.fightId} and is_final
    `;
    assert.equal(marked.length, 0);
  } finally {
    await database`alter table public.fight_members drop constraint security_test_finalization_failure`;
  }
});

test("declining requires the caller's invited membership and revokes its invite", async (t) => {
  const f = await fixture(t);
  await assert.rejects(declineMembership(randomUUID(), f.fightId, database), /not invited/);
  await assert.rejects(declineMembership(f.owner, f.fightId, database), /cannot be declined/);
  await database`
    update public.fight_members set state = 'invited' where fight_id = ${f.fightId} and user_id = ${f.peer}
  `;
  await database`
    insert into public.fight_invites (fight_id, invited_user_id, token_hash, expires_at)
    values (${f.fightId}, ${f.peer}, ${randomUUID()}, now() + interval '1 day')
  `;
  await declineMembership(f.peer, f.fightId, database);
  await declineMembership(f.peer, f.fightId, database);
  const [member] = await database`
    select state from public.fight_members where fight_id = ${f.fightId} and user_id = ${f.peer}
  `;
  const [invite] = await database`select revoked_at from public.fight_invites where fight_id = ${f.fightId}`;
  assert.equal(member.state, "declined");
  assert.ok(invite.revoked_at);
});

test("deleting an owner with other participants removes their account and private data", async (t) => {
  const f = await fixture(t);
  const seriesId = randomUUID();
  const peerFightId = randomUUID();
  await database`
    insert into public.fight_series (id, owner_id, duration_seconds, name, time_zone, current_fight_id)
    values (${seriesId}, ${f.owner}, 259200, 'Owner series', 'UTC', ${f.fightId})
  `;
  await database`update public.fights set series_id = ${seriesId} where id = ${f.fightId}`;
  for (const userId of f.users) {
    await database`insert into public.fight_series_members (series_id, user_id) values (${seriesId}, ${userId})`;
  }
  await database`
    insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
    values (${peerFightId}, ${f.peer}, 'Peer fight', 'live', ${f.startsAt}, ${f.endsAt}, 'UTC', 'highest_total', 'shared')
  `;
  for (const userId of f.users) {
    await database`
      insert into public.fight_members (fight_id, user_id, state) values (${peerFightId}, ${userId}, 'accepted')
    `;
  }
  await database`
    insert into private.apple_sign_in_tokens (
      user_id, apple_subject, encrypted_refresh_token, encryption_iv, encryption_tag
    ) values (${f.owner}, 'fixture', 'invalid-fixture', 'invalid-fixture', 'invalid-fixture')
  `;
  await database`
    insert into private.healthkit_sync_diagnostics (
      user_id, background_refresh_status, delivery_registration_status, app_version, app_build
    ) values (${f.owner}, 'available', 'enabled', '1.0.0', '1')
  `;
  await database`
    insert into private.fight_join_attempts (user_id, client_ip) values (${f.owner}, '192.0.2.1')
  `;
  assert.equal(await deleteAccount(f.owner, database), false);
  for (const table of ["public.profiles", "public.fight_members", "public.data_sources",
    "private.apple_sign_in_tokens", "private.healthkit_sync_diagnostics", "private.fight_join_attempts"]) {
    const remaining = await database`select user_id from ${database(table)} where user_id = ${f.owner}`;
    assert.equal(remaining.length, 0, table);
  }
  assert.equal((await database`select id from auth.users where id = ${f.owner}`).length, 0);
  assert.equal((await database`select id from public.fights where id = ${f.fightId}`).length, 0);
  assert.equal((await database`select id from public.fight_series where id = ${seriesId}`).length, 0);
  assert.equal((await database`select id from auth.users where id = ${f.peer}`).length, 1);
  assert.equal((await database`select id from public.fights where id = ${peerFightId}`).length, 1);
});
