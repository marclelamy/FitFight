import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import postgres from "postgres";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { closeDueFightsForUser } from "./close-due-fights-supabase-query";

const databaseURL = process.env.DATABASE_URL;
if (process.env.CI !== "true" || !databaseURL
  || !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)) {
  throw new Error("These tests require the disposable local database in cloud CI");
}
const database = postgres(databaseURL, { max: 1 });
after(() => database.end());

async function fixture(t: TestContext) {
  const users = Array.from({ length: 5 }, () => randomUUID());
  const [owner, peer, invited, declined, outsider] = users;
  const shared = randomUUID();
  const ownerOnly = randomUUID();
  const unrelated = randomUUID();
  t.after(async () => {
    await database`delete from public.fights where owner_id = any(${database.array(users)}::uuid[])`;
    await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
  });
  for (const userId of users) {
    await database`insert into auth.users (id) values (${userId})`;
  }
  for (const fight of [
    { id: shared, owner, starts: "2026-03-28T23:00:00Z", ends: "2026-03-29T22:00:00Z" },
    { id: ownerOnly, owner, starts: "2026-03-01T00:00:00Z", ends: "2026-03-31T00:00:00Z" },
    { id: unrelated, owner: outsider, starts: "2026-03-01T00:00:00Z", ends: "2026-03-31T00:00:00Z" },
  ]) {
    await database`
      insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
      values (${fight.id}, ${fight.owner}, 'Snapshot fixture', 'live', ${fight.starts}, ${fight.ends},
        'Europe/Paris', 'highest_total', 'shared')
    `;
  }
  for (const member of [
    { fight: shared, user: owner, state: "accepted" },
    { fight: shared, user: peer, state: "accepted" },
    { fight: shared, user: invited, state: "invited" },
    { fight: shared, user: declined, state: "declined" },
    { fight: ownerOnly, user: peer, state: "accepted" },
    { fight: unrelated, user: peer, state: "accepted" },
    { fight: unrelated, user: outsider, state: "accepted" },
  ]) {
    await database`
      insert into public.fight_members (fight_id, user_id, state)
      values (${member.fight}, ${member.user}, ${member.state})
    `;
  }
  for (const userId of [owner, peer, outsider]) {
    for (const day of ["2026-03-05", "2026-03-29", "2026-03-30"]) {
      await database`insert into public.step_days (user_id, day, steps) values (${userId}, ${day}, 123)`;
    }
  }
  return { owner, peer, invited, declined, outsider, shared, ownerOnly, unrelated };
}

test("snapshot preserves invited, declined, owner-only and day-specific RLS access", async (t) => {
  const f = await fixture(t);
  const owner = await readFightSnapshot(f.owner, "Europe/Paris", database);
  assert.deepEqual(new Set(owner.fights.map((fight) => fight.id)), new Set([f.shared, f.ownerOnly]));
  assert.ok(owner.members.every((member) => member.fight_id === f.shared));
  assert.deepEqual(owner.step_days.filter((day) => day.user_id === f.peer).map((day) => day.day), ["2026-03-29"]);
  assert.equal(owner.step_days.filter((day) => day.user_id === f.owner).length, 3);
  assert.ok(!owner.step_days.some((day) => day.user_id === f.outsider));

  const invited = await readFightSnapshot(f.invited, "Europe/Paris", database);
  assert.deepEqual(invited.fights.map((fight) => fight.id), [f.shared]);
  assert.deepEqual(invited.members.map((member) => member.user_id), [f.invited]);
  assert.deepEqual(new Set(invited.profiles.map((profile) => profile.user_id)), new Set([f.owner, f.invited]));
  assert.deepEqual(invited.step_days, []);

  const declined = await readFightSnapshot(f.declined, "Europe/Paris", database);
  assert.deepEqual(declined, { fights: [], members: [], profiles: [], series: [], step_days: [] });

  // max: 1 forces this assertion to inspect the same pooled connection used above.
  const [connection] = await database`
    select current_user = session_user as restored_role,
      nullif(current_setting('request.jwt.claim.sub', true), '') is null as cleared_subject
  `;
  assert.equal(connection.restored_role, true);
  assert.equal(connection.cleared_subject, true);
});

test("snapshot handles a DST day without exposing a midnight cutoff day or deleted profiles", async (t) => {
  const f = await fixture(t);
  await database`delete from public.fights where id = ${f.ownerOnly}`;
  await database`update public.profiles set deleted_at = now() where user_id = ${f.invited}`;
  const snapshot = await readFightSnapshot(f.owner, "Europe/Paris", database);
  assert.deepEqual(new Set(snapshot.step_days.map((day) => day.day)), new Set(["2026-03-29"]));
  assert.ok(!snapshot.profiles.some((profile) => profile.user_id === f.invited));

  const peer = await readFightSnapshot(f.peer, "Europe/Paris", database);
  assert.ok(peer.fights.some((fight) => fight.id === f.unrelated));
  assert.ok(peer.members.some((member) => member.user_id === f.outsider));
  const ownerAgain = await readFightSnapshot(f.owner, "Europe/Paris", database);
  assert.ok(!ownerAgain.fights.some((fight) => fight.id === f.unrelated));
  assert.ok(!ownerAgain.members.some((member) => member.user_id === f.outsider));
});

test("refresh maintenance closes only the caller's accepted fights", async (t) => {
  const f = await fixture(t);
  const admin = { from: () => { throw new Error("fixture has no recurring series"); } };
  const result = await closeDueFightsForUser(
    f.owner, admin as never, new Date("2026-09-05T12:00:00Z"), database,
  );
  assert.deepEqual(result.fightIds, [f.shared]);
  const rows = await database`select id, state from public.fights where id = any(${database.array([
    f.shared, f.ownerOnly, f.unrelated,
  ])}::uuid[])`;
  assert.equal(rows.find((row) => row.id === f.shared)?.state, "final");
  assert.equal(rows.find((row) => row.id === f.ownerOnly)?.state, "live");
  assert.equal(rows.find((row) => row.id === f.unrelated)?.state, "live");
});
