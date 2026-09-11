-- Daily AI challenge-status notifications: custom alert/recap bodies on the outbox.

alter table private.notification_intents
  add column alert_body text,
  add column recap_body text;

alter table private.notification_intents
  drop constraint notification_intents_kind;

alter table private.notification_intents
  add constraint notification_intents_kind check (
    kind in ('fight_ended', 'grace_reminder', 'fight_finalized', 'daily_status')
  );

alter table private.notification_intents
  drop constraint notification_intents_slot;

alter table private.notification_intents
  add constraint notification_intents_slot check (
    slot in ('t0', 't12', 't18', 't23', 'final', 'daily')
  );

alter table private.notification_intents
  add constraint notification_intents_alert_body_nonempty check (
    alert_body is null or btrim(alert_body) <> ''
  );

alter table private.notification_intents
  add constraint notification_intents_recap_body_nonempty check (
    recap_body is null or btrim(recap_body) <> ''
  );

alter table private.notification_intents
  add constraint notification_intents_daily_status_bodies check (
    kind <> 'daily_status'
    or (alert_body is not null and recap_body is not null)
  );
