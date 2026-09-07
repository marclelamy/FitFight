import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { claimReferralRequestSchema } from "@/lib/types/referrals/referral";
import { claimReferral } from "./referrals-supabase-query";

const databaseURL = process.env.DATABASE_URL;
if (process.env.CI !== "true" || !databaseURL
  || !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)) {
  throw new Error("These tests require the disposable local database in cloud CI");
}
const database = postgres(databaseURL, { max: 3 });
after(() => database.end());

test("referrals are stable, first-claim-only, private account relationships with deletion cleanup", async (t) => {
  const users = Array.from({ length: 4 }, () => randomUUID());
  const [first, second, recipient, otherRecipient] = users;
  t.after(async () => {
    await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
  });
  for (const userId of users) {
    await database`insert into auth.users (id) values (${userId})`;
  }

  const links = await Promise.all([first, second].map(async (userId) => {
    const [row] = await database`select referral_code as code from public.profiles where user_id = ${userId}`;
    return claimReferralRequestSchema.parse(row);
  }));
  assert.notEqual(links[0].code, first);
  assert.notEqual(links[0].code, links[1].code);
  assert.deepEqual(await claimReferral(first, links[0], database), { recorded: false });
  assert.deepEqual(await claimReferral(recipient, { code: randomUUID() }, database), { recorded: false });
  assert.deepEqual(await claimReferral(randomUUID(), links[0], database), { recorded: false });

  const claims = await Promise.all([
    claimReferral(recipient, links[0], database), claimReferral(recipient, links[1], database),
  ]);
  assert.equal(claims.filter((claim) => claim.recorded).length, 1);
  const [original] = await database`
    select referrer_user_id, created_at from private.referrals where referred_user_id = ${recipient}
  `;
  assert.ok([first, second].includes(original.referrer_user_id));
  assert.deepEqual(await claimReferral(recipient, links[0], database), { recorded: false });
  assert.deepEqual(await claimReferral(recipient, links[1], database), { recorded: false });
  const [unchanged] = await database`
    select referrer_user_id, created_at from private.referrals where referred_user_id = ${recipient}
  `;
  assert.deepEqual(unchanged, original);

  await database`update public.profiles set handle = ${"ref_" + first.slice(0, 8)} where user_id = ${first}`;
  await database`update public.profiles set deleted_at = now() where user_id = ${first}`;
  assert.deepEqual(await claimReferral(otherRecipient, links[0], database), { recorded: false });
  await database`update public.profiles set deleted_at = null where user_id = ${first}`;
  await database`update public.profiles set deleted_at = now() where user_id = ${otherRecipient}`;
  assert.deepEqual(await claimReferral(otherRecipient, links[0], database), { recorded: false });
  await database`update public.profiles set deleted_at = null where user_id = ${otherRecipient}`;
  assert.deepEqual(await claimReferral(otherRecipient, links[0], database), { recorded: true });

  await assert.rejects(database`
    insert into private.referrals (referred_user_id, referrer_user_id) values (${second}, ${second})
  `, /referrals_not_self/);

  await database`delete from auth.users where id = ${recipient}`;
  assert.equal((await database`select * from private.referrals where referred_user_id = ${recipient}`).length, 0);
  await database`delete from auth.users where id = ${first}`;
  assert.equal((await database`select * from private.referrals where referred_user_id = ${otherRecipient}`).length, 0);
  assert.deepEqual(await claimReferral(otherRecipient, links[0], database), { recorded: false });
});
