import { notificationCopyKeySchema } from "@/lib/types/notifications/notification-intent";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";

const copy: Record<
  ReturnType<typeof notificationCopyKeySchema.parse>,
  Record<NotificationLocale, { title: string; body: string }>
> = {
  fight_ended_everyone: {
    en: { title: "FitFight", body: "A fight ended. Open FitFight." },
    fr: { title: "FitFight", body: "Un défi est terminé. Ouvrez FitFight." },
  },
  fight_ended_sync: {
    en: { title: "FitFight", body: "A fight ended. Open FitFight to sync your steps." },
    fr: { title: "FitFight", body: "Un défi est terminé. Ouvrez FitFight pour synchroniser vos pas." },
  },
  grace_12h: {
    en: { title: "FitFight", body: "12 hours left. Open FitFight or you lose." },
    fr: { title: "FitFight", body: "12 heures restantes. Ouvrez FitFight ou vous perdez." },
  },
  grace_6h: {
    en: { title: "FitFight", body: "6 hours left. Open FitFight or you lose." },
    fr: { title: "FitFight", body: "6 heures restantes. Ouvrez FitFight ou vous perdez." },
  },
  grace_1h: {
    en: { title: "FitFight", body: "Last hour. Open FitFight or you lose." },
    fr: { title: "FitFight", body: "Dernière heure. Ouvrez FitFight ou vous perdez." },
  },
  fight_finalized: {
    en: { title: "FitFight", body: "The result is in. Open FitFight." },
    fr: { title: "FitFight", body: "Le résultat est tombé. Ouvrez FitFight." },
  },
  daily_status: {
    en: { title: "FitFight", body: "Your fight has an update. Open FitFight." },
    fr: { title: "FitFight", body: "Votre défi a une mise à jour. Ouvrez FitFight." },
  },
};

export function notificationAlert(
  copyKey: string,
  locale: NotificationLocale | null | undefined,
): { title: string; body: string } {
  const key = notificationCopyKeySchema.parse(copyKey);
  const language: NotificationLocale = locale === "fr" ? "fr" : "en";
  return copy[key][language];
}
