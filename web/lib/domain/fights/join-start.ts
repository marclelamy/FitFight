import { civilDayStamp, resolveTimeZone } from "@/lib/scoring/civil-day";
import type { FightJoinStart } from "@/lib/types/fights/join-start";

export function canDeferFightJoin(input: {
  recurring: boolean;
  paused: boolean;
  startsAt: string;
  timeZone: string;
  now: Date;
}): boolean {
  if (!input.recurring || input.paused) {
    return false;
  }
  const startMs = Date.parse(input.startsAt);
  if (!Number.isFinite(startMs) || startMs >= input.now.getTime()) {
    return false;
  }
  const timeZone = resolveTimeZone(input.timeZone);
  return civilDayStamp(input.now, timeZone) > civilDayStamp(new Date(startMs), timeZone);
}

export function fightJoinMemberState(
  start: FightJoinStart,
  canDefer: boolean,
): "accepted" | "deferred" | null {
  switch (start) {
    case "now":
      return "accepted";
    case "next":
      return canDefer ? "deferred" : null;
    default: {
      const exhaustive: never = start;
      return exhaustive;
    }
  }
}
