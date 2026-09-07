const CIVIL_DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isCivilDay(day: string): boolean {
  const match = CIVIL_DAY.exec(day);
  if (!match) {
    return false;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const date = Number(match[3]);
  const utc = new Date(Date.UTC(year, month - 1, date));
  return (
    utc.getUTCFullYear() === year &&
    utc.getUTCMonth() === month - 1 &&
    utc.getUTCDate() === date
  );
}

export function resolveTimeZone(timeZone: string | null | undefined): string {
  const tz = timeZone?.trim() || "UTC";
  try {
    Intl.DateTimeFormat("en-US", { timeZone: tz }).format();
    return tz;
  } catch {
    return "UTC";
  }
}

export function addCalendarDay(day: string): string {
  const match = CIVIL_DAY.exec(day);
  if (!match) {
    throw new Error("invalid civil day");
  }
  const utc = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + 1));
  return utc.toISOString().slice(0, 10);
}

function tzOffsetMilliseconds(instant: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const num = (type: Intl.DateTimeFormatPartTypes): number => {
    const value = parts.find((part) => part.type === type)?.value;
    return Number(value);
  };
  const asUtc = Date.UTC(
    num("year"),
    num("month") - 1,
    num("day"),
    num("hour"),
    num("minute"),
    num("second"),
  );
  return asUtc - instant.getTime();
}

export function wallMidnightToUtc(day: string, timeZone: string): Date {
  const match = CIVIL_DAY.exec(day);
  if (!match) {
    throw new Error("invalid civil day");
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const date = Number(match[3]);
  const utcGuess = Date.UTC(year, month - 1, date, 0, 0, 0);
  const offset = tzOffsetMilliseconds(new Date(utcGuess), timeZone);
  let instant = utcGuess - offset;
  const refined = tzOffsetMilliseconds(new Date(instant), timeZone);
  if (refined !== offset) {
    instant = utcGuess - refined;
  }
  return new Date(instant);
}

export function civilDayBounds(
  day: string,
  timeZone: string,
): { startsAt: Date; endsAt: Date; externalRecordId: string } {
  if (!isCivilDay(day)) {
    throw new Error("invalid civil day");
  }
  const zone = resolveTimeZone(timeZone);
  const startsAt = wallMidnightToUtc(day, zone);
  const endsAt = wallMidnightToUtc(addCalendarDay(day), zone);
  return {
    startsAt,
    endsAt,
    externalRecordId: `day:${day}`,
  };
}

export function civilDayStamp(instant: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: resolveTimeZone(timeZone),
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

