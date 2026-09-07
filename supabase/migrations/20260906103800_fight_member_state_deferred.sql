-- People who join a repeating fight after it started can wait for the next
-- window. They stay visible on this fight without counting in standings.
alter type public.fight_member_state add value if not exists 'deferred';
