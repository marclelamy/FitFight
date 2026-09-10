import type { OutcomeRule } from "../types/database";

export type ScoreMemberInput = {
  userId: string;
  value: number;
  personalTarget: number | null;
};

export type ScoreMemberResult = {
  userId: string;
  currentValue: number;
  rank: number;
  outcomeMinor: number;
  hitGoal: boolean;
};

export function fightPot(stakeMinor: number | null | undefined, acceptedCount: number): number {
  const stake = stakeMinor ?? 0;
  if (stake <= 0 || acceptedCount <= 0) {
    return 0;
  }
  return stake * acceptedCount;
}

export function competitionRank(value: number, values: number[]): number {
  return values.filter((other) => other > value).length + 1;
}

function splitEvenly(total: number, userIds: string[]): Map<string, number> {
  const out = new Map<string, number>();
  const ordered = [...userIds].sort((a, b) => a.localeCompare(b));
  if (ordered.length === 0 || total <= 0) {
    for (const id of ordered) {
      out.set(id, 0);
    }
    return out;
  }
  const base = Math.floor(total / ordered.length);
  const remainder = total % ordered.length;
  ordered.forEach((id, index) => {
    out.set(id, base + (index < remainder ? 1 : 0));
  });
  return out;
}

function allocateProportional(members: ScoreMemberInput[], pot: number): Map<string, number> {
  const out = new Map<string, number>();
  const total = members.reduce((sum, member) => sum + member.value, 0);
  if (pot <= 0 || total <= 0) {
    for (const member of members) {
      out.set(member.userId, 0);
    }
    return out;
  }

  const exact = members.map((member) => ({
    userId: member.userId,
    exact: (member.value / total) * pot,
  }));
  const floors = exact.map((row) => ({
    userId: row.userId,
    amount: Math.floor(row.exact),
    frac: row.exact - Math.floor(row.exact),
  }));
  let remain = pot - floors.reduce((sum, row) => sum + row.amount, 0);
  const order = [...floors].sort((a, b) => {
    if (b.frac !== a.frac) {
      return b.frac - a.frac;
    }
    return a.userId.localeCompare(b.userId);
  });
  for (const row of order) {
    if (remain <= 0) {
      break;
    }
    row.amount += 1;
    remain -= 1;
  }
  for (const row of floors) {
    out.set(row.userId, row.amount);
  }
  return out;
}

function goalTarget(
  member: ScoreMemberInput,
  defaultGoalValue: number | null,
): number | null {
  if (member.personalTarget !== null && Number.isFinite(member.personalTarget)) {
    return member.personalTarget;
  }
  if (defaultGoalValue !== null && Number.isFinite(defaultGoalValue)) {
    return defaultGoalValue;
  }
  return null;
}

export function scoreFight(input: {
  outcomeRule: OutcomeRule;
  stakeMinor: number | null;
  defaultGoalValue: number | null;
  members: ScoreMemberInput[];
}): ScoreMemberResult[] {
  const members = input.members;
  const values = members.map((member) => member.value);
  const pot = fightPot(input.stakeMinor, members.length);
  const outcomes = new Map<string, number>();

  switch (input.outcomeRule) {
    case "highest_total": {
      const top = members.reduce((max, member) => Math.max(max, member.value), 0);
      const winners = members.filter((member) => member.value === top).map((m) => m.userId);
      const split = top > 0 ? splitEvenly(pot, winners) : new Map<string, number>();
      for (const member of members) {
        outcomes.set(member.userId, split.get(member.userId) ?? 0);
      }
      break;
    }
    case "proportional": {
      const split = allocateProportional(members, pot);
      for (const member of members) {
        outcomes.set(member.userId, split.get(member.userId) ?? 0);
      }
      break;
    }
    case "hit_your_goal": {
      const hitters = members
        .filter((member) => {
          const target = goalTarget(member, input.defaultGoalValue);
          return target !== null && member.value >= target;
        })
        .map((member) => member.userId);
      const split = splitEvenly(pot, hitters);
      for (const member of members) {
        outcomes.set(member.userId, split.get(member.userId) ?? 0);
      }
      break;
    }
    default: {
      const exhaustive: never = input.outcomeRule;
      throw new Error(`Unsupported outcome rule: ${String(exhaustive)}`);
    }
  }

  return members
    .map((member) => {
      const target = goalTarget(member, input.defaultGoalValue);
      return {
        userId: member.userId,
        currentValue: member.value,
        rank: competitionRank(member.value, values),
        outcomeMinor: outcomes.get(member.userId) ?? 0,
        hitGoal: target !== null && member.value >= target,
      };
    })
    .sort((a, b) => a.rank - b.rank || a.userId.localeCompare(b.userId));
}

export function scoreFightAtFinal(input: {
  outcomeRule: OutcomeRule;
  stakeMinor: number | null;
  defaultGoalValue: number | null;
  members: Array<ScoreMemberInput & { complete: boolean }>;
}): ScoreMemberResult[] {
  switch (input.outcomeRule) {
    case "highest_total":
    case "proportional":
    case "hit_your_goal": {
      const complete = input.members.filter((member) => member.complete);
      const incomplete = input.members.filter((member) => !member.complete);
      if (complete.length === 0) {
        return scoreFight(input).map((row) => ({ ...row, rank: 1, outcomeMinor: 0 }));
      }

      const incompleteRank = complete.length + 1;
      return [
        ...scoreFight({ ...input, members: complete }),
        ...incomplete.map((member) => {
          const target = goalTarget(member, input.defaultGoalValue);
          return {
            userId: member.userId,
            currentValue: member.value,
            rank: incompleteRank,
            outcomeMinor: 0,
            hitGoal: target !== null && member.value >= target,
          };
        }),
      ].sort((a, b) => a.rank - b.rank || a.userId.localeCompare(b.userId));
    }
    default: {
      const exhaustive: never = input.outcomeRule;
      throw new Error(`Unsupported outcome rule: ${String(exhaustive)}`);
    }
  }
}
