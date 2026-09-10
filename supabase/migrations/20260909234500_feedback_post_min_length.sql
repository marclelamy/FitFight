-- Bugs & requests title and details only need one character each.
alter table public.feedback_posts
  drop constraint feedback_posts_title_len,
  add constraint feedback_posts_title_len check (
    char_length(title) between 1 and 80
  ),
  drop constraint feedback_posts_body_len,
  add constraint feedback_posts_body_len check (
    char_length(body) between 1 and 2000
  );
