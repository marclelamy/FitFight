begin;
select plan(15);

select has_table('private', 'device_installations', 'Device installations are private');
select has_table('private', 'notification_intents', 'Notification intents are private');
select has_table('private', 'notification_deliveries', 'Notification deliveries are private');

select ok(
  (select relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'device_installations'),
  'Device installations have RLS'
);
select ok(
  (select relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'notification_intents'),
  'Notification intents have RLS'
);
select ok(
  (select relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'notification_deliveries'),
  'Notification deliveries have RLS'
);

select is(
  has_table_privilege('anon', 'private.device_installations', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'Anonymous clients cannot access device installations'
);
select is(
  has_table_privilege('authenticated', 'private.device_installations', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'App clients cannot access device installations directly'
);
select ok(
  has_table_privilege('service_role', 'private.device_installations', 'INSERT'),
  'The backend can record device installations'
);

select is(
  has_table_privilege('anon', 'private.notification_intents', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'Anonymous clients cannot access notification intents'
);
select is(
  has_table_privilege('authenticated', 'private.notification_intents', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'App clients cannot access notification intents directly'
);
select ok(
  has_table_privilege('service_role', 'private.notification_intents', 'INSERT'),
  'The backend can record notification intents'
);

select is(
  has_table_privilege('anon', 'private.notification_deliveries', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'Anonymous clients cannot access notification deliveries'
);
select is(
  has_table_privilege('authenticated', 'private.notification_deliveries', 'SELECT,INSERT,UPDATE,DELETE'),
  false,
  'App clients cannot access notification deliveries directly'
);
select ok(
  has_table_privilege('service_role', 'private.notification_deliveries', 'INSERT'),
  'The backend can record notification deliveries'
);

select * from finish();
rollback;
