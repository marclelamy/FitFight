begin;
select plan(8);

select is((
  select count(*)::integer
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('anon'), ('authenticated')) as client(role_name)
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
    and (has_table_privilege(client.role_name, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
      or has_any_column_privilege(client.role_name, c.oid, 'SELECT,INSERT,UPDATE,REFERENCES'))
), 0, 'clients have no effective table, view, or column privileges, including inherited and PUBLIC grants');

select is((
  select count(*)::integer
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('anon'), ('authenticated')) as client(role_name)
  where n.nspname = 'public' and c.relkind = 'S'
    and has_sequence_privilege(client.role_name, c.oid, 'USAGE,SELECT,UPDATE')
), 0, 'clients have no sequence privileges');

select ok(not has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.handle_new_user()', 'EXECUTE'),
  'signup trigger function cannot be called directly');
select is((
  select count(*)::integer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join (values ('anon'), ('authenticated')) as client(role_name)
  where n.nspname = 'public' and has_function_privilege(client.role_name, p.oid, 'EXECUTE')
    and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
      and d.objid = p.oid and d.deptype = 'e')
), 0, 'clients cannot execute application-owned public functions');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE')
  and not has_schema_privilege('anon', 'private', 'USAGE'), 'private policy helpers stay server-only');

create table public.client_access_default_probe (id bigint generated always as identity);
select ok(not has_table_privilege('authenticated', 'public.client_access_default_probe', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon', 'public.client_access_default_probe', 'SELECT,INSERT,UPDATE,DELETE'),
  'future tables do not restore client access');
select ok(not has_sequence_privilege('authenticated', 'public.client_access_default_probe_id_seq', 'USAGE,SELECT,UPDATE')
  and not has_sequence_privilege('anon', 'public.client_access_default_probe_id_seq', 'USAGE,SELECT,UPDATE'),
  'future sequences do not restore client access');

create function public.client_access_function_probe() returns integer language sql as 'select 1';
select ok(not has_function_privilege('authenticated', 'public.client_access_function_probe()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.client_access_function_probe()', 'EXECUTE'),
  'future functions do not restore client access through PUBLIC defaults');

select * from finish();
rollback;
