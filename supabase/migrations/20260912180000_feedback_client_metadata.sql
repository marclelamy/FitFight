-- Client debug snapshot on Bugs & requests posts and comments.
-- Non-destructive ADD COLUMN only.

alter table public.feedback_posts
  add column metadata jsonb not null default '{}'::jsonb;

alter table public.feedback_comments
  add column metadata jsonb not null default '{}'::jsonb;

alter table public.feedback_posts
  add constraint feedback_posts_metadata_object
  check (jsonb_typeof(metadata) = 'object');

alter table public.feedback_comments
  add constraint feedback_comments_metadata_object
  check (jsonb_typeof(metadata) = 'object');

alter table public.feedback_posts
  add constraint feedback_posts_metadata_size
  check (octet_length(metadata::text) <= 8192);

alter table public.feedback_comments
  add constraint feedback_comments_metadata_size
  check (octet_length(metadata::text) <= 8192);
