import assert from "node:assert/strict";
import { test } from "node:test";
import {
  JOINABLE_MEMBER_CAP,
} from "./join-fight-supabase-query";
import {
  joinableFightSummarySchema,
  joinFightRequestSchema,
  leaveFightRequestSchema,
} from "@/lib/types/fights/joinable-fight";

test("join requires a code or fight id", () => {
  assert.equal(joinFightRequestSchema.safeParse({}).success, false);
  assert.equal(joinFightRequestSchema.parse({ code: "K7M2" }).code, "K7M2");
  assert.equal(
    joinFightRequestSchema.parse({ fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }).fightId,
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  );
});

test("join defaults to this round and can ask for the next round", () => {
  assert.equal(joinFightRequestSchema.parse({ code: "K7M2" }).start, "now");
  assert.equal(joinFightRequestSchema.parse({ code: "K7M2", start: "next" }).start, "next");
  assert.equal(joinFightRequestSchema.safeParse({ code: "K7M2", start: "later" }).success, false);
});

test("joinable summaries never carry scores", () => {
  const summary = joinableFightSummarySchema.parse({
    fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    seriesId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    name: "Office steps",
    joinCode: "K7M2",
    ownerHandle: "maya",
    actionText: "Cook dinner",
    startsAt: "2026-09-04T12:00:00.000Z",
    endsAt: "2026-09-11T12:00:00.000Z",
    memberCount: 3,
    recurring: true,
    alreadyMember: false,
    canJoinNext: true,
  });
  assert.equal("score" in summary, false);
  assert.equal("standings" in summary, false);
  assert.equal(summary.memberCount, 3);
  assert.equal(JOINABLE_MEMBER_CAP, 50);
});

test("leave requires a fight id", () => {
  assert.equal(leaveFightRequestSchema.safeParse({}).success, false);
  assert.equal(
    leaveFightRequestSchema.parse({ fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }).fightId,
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  );
});
