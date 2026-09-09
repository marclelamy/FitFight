begin;
select plan(12);

select has_table('public', 'media_objects', 'media objects exist');
select has_table('public', 'fight_posts', 'fight posts exist');
select has_table('public', 'fight_post_media', 'fight post media exist');
select has_table('private', 'fight_post_reports', 'post reports stay private');
select has_table('private', 'feed_blocks', 'feed blocks stay private');

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'avatar_media_id'
  ),
  'profiles can point at a photo'
);

select is(
  (select public from storage.buckets where id = 'user-media'),
  false,
  'user-media is a private bucket'
);
select is(
  (select file_size_limit from storage.buckets where id = 'user-media'),
  52428800::bigint,
  'user-media allows photos and short videos'
);

select is(
  has_table_privilege('authenticated', 'public.media_objects', 'INSERT'),
  false,
  'clients cannot insert media rows'
);
select is(
  has_table_privilege('authenticated', 'public.fight_posts', 'INSERT'),
  false,
  'clients cannot insert fight posts'
);
select is(
  has_table_privilege('authenticated', 'private.fight_post_reports', 'SELECT'),
  false,
  'clients cannot read post reports'
);
select is(
  has_table_privilege('authenticated', 'private.feed_blocks', 'SELECT'),
  false,
  'clients cannot read feed blocks'
);

select * from finish();
rollback;
