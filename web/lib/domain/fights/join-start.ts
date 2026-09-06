import type { FightJoinStart } from "@/lib/types/fights/join-start";

export function canDeferFightJoin(input: {
  recurring: boolean;
  paused: boolean;
  startsAt: string;
  now: Date;
}): boolean {
  return input.recurring && !input.paused && Date.parse(input.startsAt) < input.now.getTime();
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

