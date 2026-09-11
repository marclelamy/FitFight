import type { DailyStatusStanding } from "@/lib/types/notifications/daily-status";

type MemberStanding = {
  userId: string;
  rank: number | null;
};

export function dailyStatusStanding(
  userId: string,
  members: MemberStanding[],
): DailyStatusStanding {
  const accepted = members.filter((member) => member.rank != null);
  const mine = accepted.find((member) => member.userId === userId);
  if (!mine?.rank) {
    return accepted.length <= 1 ? "leading" : "behind";
  }

  const ranks = accepted.map((member) => member.rank as number);
  const bestRank = Math.min(...ranks);
  const worstRank = Math.max(...ranks);
  const leaders = accepted.filter((member) => member.rank === bestRank);

  if (mine.rank === worstRank && worstRank > bestRank) {
    return "last";
  }
  if (leaders.some((member) => member.userId === userId)) {
    return leaders.length > 1 ? "tied_for_lead" : "leading";
  }
  if (mine.rank < worstRank) {
    return "ahead";
  }
  return "behind";
}
