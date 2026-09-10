import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  BlockFeedAuthorResponse,
  CreateFeedPostsRequest,
  CreateFightPostRequest,
  FeedAudience,
  FeedPeopleResponse,
  FightPost,
  FightPostBatchResponse,
  FightPostListResponse,
  FightPostReaction,
  FightPostResponse,
  FightPostTag,
  ListFeedPeopleQuery,
  ListFightPostsQuery,
  ReportFightPostRequest,
  ReportFightPostResponse,
} from "@/lib/types/feed/fight-post";
import {
  loadReadyMedia,
  mapMedia,
  signMediaUrl,
  type MediaRow,
} from "./media-supabase-query";

const POST_LIMIT_PER_DAY = 20;

export type VisibleFightPost = {
  id: string;
  audience: FeedAudience;
  fight_id: string | null;
  author_id: string;
};

type PostRow = {
  id: string;
  audience: FeedAudience;
  fight_id: string | null;
  fight_name: string;
  body: string;
  created_at: Date | string;
  author_id: string;
  author_handle: string;
  author_display_name: string;
  avatar_id: string | null;
  avatar_kind: MediaRow["kind"] | null;
  avatar_purpose: MediaRow["purpose"] | null;
  avatar_status: MediaRow["status"] | null;
  avatar_object_path: string | null;
  avatar_original_filename: string | null;
  avatar_content_type: MediaRow["content_type"] | null;
  avatar_byte_size: string | number | null;
  avatar_width: number | null;
  avatar_height: number | null;
  avatar_duration_ms: number | null;
  avatar_sha256: string | null;
  avatar_created_at: Date | string | null;
};

type AttachmentRow = MediaRow & { post_id: string };

type TagRow = {
  post_id: string;
  user_id: string;
  handle: string;
  display_name: string;
};

type ReactionRow = {
  post_id: string;
  emoji: string;
  count: number;
  mine: boolean;
};

type CountRow = {
  post_id: string;
  n: number;
};

function isoUtc(value: Date | string): string {
  return new Date(value).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function cursorStamp(value: Date | string): string {
  return new Date(value).toISOString();
}

function parseCursor(cursor: string | undefined): { createdAt: string; id: string } | null {
  if (!cursor) return null;
  const separator = cursor.lastIndexOf("|");
  if (separator <= 0) {
    throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
  }
  const createdAt = cursor.slice(0, separator);
  const id = cursor.slice(separator + 1);
  if (!Number.isFinite(Date.parse(createdAt)) || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
  }
  return { createdAt, id };
}

async function requireRosterMember(
  userId: string,
  fightId: string,
  database: Sql,
): Promise<void> {
  const [member] = await database<{ state: string }[]>`
    select state
    from public.fight_members
    where fight_id = ${fightId}
      and user_id = ${userId}
      and state in ('accepted', 'deferred')
  `;
  if (!member) {
    throw new ApiError(403, ERROR_CODES.forbidden, "Join this fight to see its posts");
  }
}

export async function loadVisiblePost(
  userId: string,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<VisibleFightPost> {
  const [post] = await database<VisibleFightPost[]>`
    select id, audience::text as audience, fight_id, author_id
    from public.fight_posts
    where id = ${postId}
  `;
  if (!post) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
  if (post.audience === "main") {
    if (post.author_id === userId) return post;
    const [shared] = await database<{ ok: boolean }[]>`
      select exists (
        select 1
        from public.fight_members as me
        join public.fight_members as them
          on them.fight_id = me.fight_id
        where me.user_id = ${userId}
          and them.user_id = ${post.author_id}
          and me.state in ('accepted', 'deferred')
          and them.state in ('accepted', 'deferred')
      ) as ok
    `;
    if (!shared?.ok) {
      throw new ApiError(403, ERROR_CODES.forbidden, "You cannot see that post");
    }
    return post;
  }
  if (post.audience === "fight") {
    if (!post.fight_id) {
      throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
    }
    const [member] = await database<{ state: string }[]>`
      select membership.state
      from public.fight_members as membership
      where membership.user_id = ${userId}
        and membership.state in ('accepted', 'deferred')
        and (
          membership.fight_id = ${post.fight_id}
          or exists (
            select 1
            from public.fights as posted
            join public.fights as sibling
              on sibling.series_id = posted.series_id
            where posted.id = ${post.fight_id}
              and posted.series_id is not null
              and sibling.id = membership.fight_id
          )
        )
      limit 1
    `;
    if (!member) {
      throw new ApiError(403, ERROR_CODES.forbidden, "Join this fight to see its posts");
    }
    return post;
  }
  const _exhaustive: never = post.audience;
  throw new ApiError(500, ERROR_CODES.internal, `Unhandled audience ${_exhaustive}`);
}

function avatarFromPost(row: PostRow, url: string | null) {
  if (!row.avatar_id || !row.avatar_kind || !row.avatar_purpose || !row.avatar_status
    || !row.avatar_object_path || !row.avatar_original_filename || !row.avatar_content_type
    || row.avatar_byte_size === null || row.avatar_width === null || row.avatar_height === null
    || !row.avatar_sha256 || !row.avatar_created_at) {
    return null;
  }
  return mapMedia({
    id: row.avatar_id,
    owner_id: row.author_id,
    kind: row.avatar_kind,
    purpose: row.avatar_purpose,
    status: row.avatar_status,
    object_path: row.avatar_object_path,
    original_filename: row.avatar_original_filename,
    content_type: row.avatar_content_type,
    byte_size: row.avatar_byte_size,
    width: row.avatar_width,
    height: row.avatar_height,
    duration_ms: row.avatar_duration_ms,
    sha256: row.avatar_sha256,
    created_at: row.avatar_created_at,
  }, url);
}

async function mapPosts(userId: string, rows: PostRow[], database: Sql): Promise<FightPost[]> {
  if (rows.length === 0) return [];
  const postIds = rows.map((row) => row.id);
  const attachments = await database<AttachmentRow[]>`
    select
      attachment.post_id,
      media.id, media.owner_id, media.kind::text as kind, media.purpose::text as purpose,
      media.status::text as status, media.object_path, media.original_filename,
      media.content_type, media.byte_size::text, media.width, media.height,
      media.duration_ms, media.sha256, media.created_at
    from public.fight_post_media as attachment
    join public.media_objects as media on media.id = attachment.media_id
    where attachment.post_id in ${database(postIds)}
    order by attachment.post_id, attachment.sort, media.id
  `;
  const tags = await database<TagRow[]>`
    select tag.post_id, tag.user_id, profile.handle, profile.display_name
    from public.fight_post_tags as tag
    join public.profiles as profile
      on profile.user_id = tag.user_id and profile.deleted_at is null
    where tag.post_id in ${database(postIds)}
    order by profile.handle
  `;
  const reactions = await database<ReactionRow[]>`
    select
      reaction.post_id,
      reaction.emoji,
      count(*)::int as count,
      bool_or(reaction.user_id = ${userId}) as mine
    from public.fight_post_reactions as reaction
    where reaction.post_id in ${database(postIds)}
    group by reaction.post_id, reaction.emoji
    order by count(*) desc, reaction.emoji
  `;
  const comments = await database<CountRow[]>`
    select comment.post_id, count(*)::int as n
    from public.fight_post_comments as comment
    where comment.post_id in ${database(postIds)}
      and not exists (
        select 1 from private.feed_blocks as blocked
        where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
      )
    group by comment.post_id
  `;
  const urls = new Map<string, string | null>();
  for (const row of rows) {
    if (row.avatar_object_path && !urls.has(row.avatar_object_path)) {
      urls.set(row.avatar_object_path, await signMediaUrl(row.avatar_object_path));
    }
  }
  for (const attachment of attachments) {
    if (!urls.has(attachment.object_path)) {
      urls.set(attachment.object_path, await signMediaUrl(attachment.object_path));
    }
  }

  const tagsByPost = new Map<string, FightPostTag[]>();
  for (const tag of tags) {
    const list = tagsByPost.get(tag.post_id) ?? [];
    list.push({ user_id: tag.user_id, handle: tag.handle, display_name: tag.display_name });
    tagsByPost.set(tag.post_id, list);
  }
  const reactionsByPost = new Map<string, FightPostReaction[]>();
  for (const reaction of reactions) {
    const list = reactionsByPost.get(reaction.post_id) ?? [];
    list.push({ emoji: reaction.emoji, count: reaction.count, mine: reaction.mine });
    reactionsByPost.set(reaction.post_id, list);
  }
  const commentCount = new Map(comments.map((row) => [row.post_id, row.n]));

  return rows.map((row) => ({
    id: row.id,
    audience: row.audience,
    fight_id: row.fight_id,
    fight_name: row.fight_name,
    body: row.body,
    created_at: isoUtc(row.created_at),
    mine: row.author_id === userId,
    author: {
      user_id: row.author_id,
      handle: row.author_handle,
      display_name: row.author_display_name,
      avatar: avatarFromPost(row, row.avatar_object_path ? urls.get(row.avatar_object_path) ?? null : null),
    },
    media: attachments
      .filter((attachment) => attachment.post_id === row.id)
      .map((attachment) => mapMedia(attachment, urls.get(attachment.object_path) ?? null)),
    tags: tagsByPost.get(row.id) ?? [],
    reactions: reactionsByPost.get(row.id) ?? [],
    comment_count: commentCount.get(row.id) ?? 0,
  }));
}

export async function listFightPosts(
  userId: string,
  fightId: string | undefined,
  query: ListFightPostsQuery,
  database: Sql = createDatabaseClient(),
): Promise<FightPostListResponse> {
  if (fightId) {
    await requireRosterMember(userId, fightId, database);
  }
  const cursor = parseCursor(query.cursor);
  const mainOnly = !fightId && query.scope === "main";
  const rows = cursor
    ? await database<PostRow[]>`
        select
          post.id, post.audience::text as audience, post.fight_id,
          coalesce(fight.name, '') as fight_name, post.body, post.created_at,
          post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_posts as post
        left join public.fights as fight on fight.id = post.fight_id
        join public.profiles as profile
          on profile.user_id = post.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = post.author_id
          )
          and (post.created_at, post.id) < (${cursor.createdAt}::timestamptz, ${cursor.id}::uuid)
          and (
            (
              ${fightId ?? null}::uuid is not null
              and post.audience = 'fight'
              and (
                post.fight_id = ${fightId ?? null}
                or (
                  fight.series_id is not null
                  and fight.series_id = (
                    select viewed.series_id from public.fights as viewed where viewed.id = ${fightId ?? null}
                  )
                )
              )
            )
            or (
              ${fightId ?? null}::uuid is null
              and ${mainOnly}::boolean
              and post.audience = 'main'
              and (
                post.author_id = ${userId}
                or exists (
                  select 1
                  from public.fight_members as me
                  join public.fight_members as them
                    on them.fight_id = me.fight_id
                  where me.user_id = ${userId}
                    and them.user_id = post.author_id
                    and me.state in ('accepted', 'deferred')
                    and them.state in ('accepted', 'deferred')
                )
              )
            )
            or (
              ${fightId ?? null}::uuid is null
              and not ${mainOnly}::boolean
              and post.audience = 'fight'
              and exists (
                select 1
                from public.fight_members as membership
                where membership.user_id = ${userId}
                  and membership.state in ('accepted', 'deferred')
                  and (
                    membership.fight_id = post.fight_id
                    or (
                      fight.series_id is not null
                      and exists (
                        select 1 from public.fights as sibling
                        where sibling.series_id = fight.series_id
                          and sibling.id = membership.fight_id
                      )
                    )
                  )
              )
            )
          )
        order by post.created_at desc, post.id desc
        limit ${query.limit + 1}
      `
    : await database<PostRow[]>`
        select
          post.id, post.audience::text as audience, post.fight_id,
          coalesce(fight.name, '') as fight_name, post.body, post.created_at,
          post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_posts as post
        left join public.fights as fight on fight.id = post.fight_id
        join public.profiles as profile
          on profile.user_id = post.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = post.author_id
          )
          and (
            (
              ${fightId ?? null}::uuid is not null
              and post.audience = 'fight'
              and (
                post.fight_id = ${fightId ?? null}
                or (
                  fight.series_id is not null
                  and fight.series_id = (
                    select viewed.series_id from public.fights as viewed where viewed.id = ${fightId ?? null}
                  )
                )
              )
            )
            or (
              ${fightId ?? null}::uuid is null
              and ${mainOnly}::boolean
              and post.audience = 'main'
              and (
                post.author_id = ${userId}
                or exists (
                  select 1
                  from public.fight_members as me
                  join public.fight_members as them
                    on them.fight_id = me.fight_id
                  where me.user_id = ${userId}
                    and them.user_id = post.author_id
                    and me.state in ('accepted', 'deferred')
                    and them.state in ('accepted', 'deferred')
                )
              )
            )
            or (
              ${fightId ?? null}::uuid is null
              and not ${mainOnly}::boolean
              and post.audience = 'fight'
              and exists (
                select 1
                from public.fight_members as membership
                where membership.user_id = ${userId}
                  and membership.state in ('accepted', 'deferred')
                  and (
                    membership.fight_id = post.fight_id
                    or (
                      fight.series_id is not null
                      and exists (
                        select 1 from public.fights as sibling
                        where sibling.series_id = fight.series_id
                          and sibling.id = membership.fight_id
                      )
                    )
                  )
              )
            )
          )
        order by post.created_at desc, post.id desc
        limit ${query.limit + 1}
      `;
  const page = rows.slice(0, query.limit);
  const last = page.at(-1);
  return {
    posts: await mapPosts(userId, page, database),
    next_cursor: rows.length > query.limit && last
      ? `${cursorStamp(last.created_at)}|${last.id}`
      : null,
  };
}

async function insertFightPost(
  userId: string,
  audience: FeedAudience,
  fightId: string | null,
  body: string,
  mediaIds: string[],
  tagIds: string[],
  database: Sql,
): Promise<string> {
  const [created] = await database<{ id: string }[]>`
    insert into public.fight_posts (fight_id, author_id, body, audience)
    values (${fightId}, ${userId}, ${body}, ${audience})
    returning id
  `;
  if (!created) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not save that post");
  }
  for (const [index, mediaId] of mediaIds.entries()) {
    await database`
      insert into public.fight_post_media (post_id, media_id, sort)
      values (${created.id}, ${mediaId}, ${index})
    `;
  }
  for (const tagId of tagIds) {
    await database`
      insert into public.fight_post_tags (post_id, user_id)
      values (${created.id}, ${tagId})
    `;
  }
  return created.id;
}

async function loadPostRows(ids: string[], database: Sql): Promise<PostRow[]> {
  if (ids.length === 0) return [];
  return database<PostRow[]>`
    select
      post.id, post.audience::text as audience, post.fight_id,
      coalesce(fight.name, '') as fight_name, post.body, post.created_at,
      post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
      avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
      avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
      avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
      avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
      avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
      avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
    from public.fight_posts as post
    left join public.fights as fight on fight.id = post.fight_id
    join public.profiles as profile
      on profile.user_id = post.author_id and profile.deleted_at is null
    left join public.media_objects as avatar
      on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
    where post.id in ${database(ids)}
    order by post.created_at desc, post.id desc
  `;
}

async function preparePostMedia(
  userId: string,
  mediaIds: string[],
  database: Sql,
): Promise<string[]> {
  const uniqueMediaIds = [...new Set(mediaIds)];
  const media = await loadReadyMedia(userId, uniqueMediaIds, "fight_post", database);
  if (media.length !== uniqueMediaIds.length) {
    throw new ApiError(400, ERROR_CODES.validation, "Every photo or video must be one you just uploaded");
  }
  const videoCount = media.filter((row) => row.kind === "video").length;
  if (videoCount > 1 || (videoCount > 0 && media.length > 1)) {
    throw new ApiError(400, ERROR_CODES.validation, "Post one video by itself");
  }
  if (uniqueMediaIds.length > 0) {
    const [taken] = await database<{ n: number }[]>`
      select count(*)::int as n
      from public.fight_post_media
      where media_id in ${database(uniqueMediaIds)}
    `;
    if ((taken?.n ?? 0) > 0) {
      throw new ApiError(409, ERROR_CODES.conflict, "A photo was already used on another post");
    }
  }
  return uniqueMediaIds;
}

export async function createFightPost(
  userId: string,
  fightId: string,
  input: CreateFightPostRequest,
  database: Sql = createDatabaseClient(),
): Promise<FightPostResponse> {
  await requireRosterMember(userId, fightId, database);
  const [rate] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.fight_posts
    where author_id = ${userId}
      and created_at > now() - interval '24 hours'
  `;
  if ((rate?.n ?? 0) >= POST_LIMIT_PER_DAY) {
    throw new ApiError(429, ERROR_CODES.rate_limited, "You’ve posted a few times recently. Try again later.");
  }

  const createdId = await database.begin("read write", async (sql) => {
    const mediaIds = await preparePostMedia(userId, input.media_ids, sql);
    return insertFightPost(userId, "fight", fightId, input.body, mediaIds, [], sql);
  });

  const [row] = await loadPostRows([createdId], database);
  if (!row) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that post");
  }
  const [created] = await mapPosts(userId, [row], database);
  if (!created) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that post");
  }
  return { post: created };
}

export async function createFeedPosts(
  userId: string,
  input: CreateFeedPostsRequest,
  database: Sql = createDatabaseClient(),
): Promise<FightPostBatchResponse> {
  let includeMain = false;
  const fightIds: string[] = [];
  for (const destination of input.destinations) {
    switch (destination.type) {
      case "main":
        includeMain = true;
        break;
      case "fight":
        if (!fightIds.includes(destination.fight_id)) {
          fightIds.push(destination.fight_id);
        }
        break;
      default: {
        const _exhaustive: never = destination;
        throw new ApiError(400, ERROR_CODES.validation, `Unsupported destination ${JSON.stringify(_exhaustive)}`);
      }
    }
  }
  if (!includeMain && fightIds.length === 0) {
    throw new ApiError(400, ERROR_CODES.validation, "Pick at least one place to post");
  }
  for (const fightId of fightIds) {
    await requireRosterMember(userId, fightId, database);
  }
  if (includeMain) {
    const [circle] = await database<{ n: number }[]>`
      select count(*)::int as n
      from public.fight_members
      where user_id = ${userId}
        and state in ('accepted', 'deferred')
    `;
    if ((circle?.n ?? 0) === 0) {
      throw new ApiError(403, ERROR_CODES.forbidden, "Join a fight before posting to Main");
    }
  }

  const [rate] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.fight_posts
    where author_id = ${userId}
      and created_at > now() - interval '24 hours'
  `;
  const copies = (includeMain ? 1 : 0) + fightIds.length;
  if ((rate?.n ?? 0) + copies > POST_LIMIT_PER_DAY) {
    throw new ApiError(429, ERROR_CODES.rate_limited, "You’ve posted a few times recently. Try again later.");
  }

  const wantedTags = [...new Set(input.tagged_user_ids)].filter((id) => id !== userId);
  const createdIds = await database.begin("read write", async (sql) => {
    const mediaIds = await preparePostMedia(userId, input.media_ids, sql);
    const ids: string[] = [];
    if (includeMain) {
      const mainTags = wantedTags.length === 0
        ? []
        : (await sql<{ user_id: string }[]>`
            select distinct them.user_id
            from public.fight_members as me
            join public.fight_members as them
              on them.fight_id = me.fight_id
            where me.user_id = ${userId}
              and them.user_id in ${sql(wantedTags)}
              and me.state in ('accepted', 'deferred')
              and them.state in ('accepted', 'deferred')
          `).map((row) => row.user_id);
      ids.push(await insertFightPost(userId, "main", null, input.body, mediaIds, mainTags, sql));
    }
    for (const fightId of fightIds) {
      const fightTags = wantedTags.length === 0
        ? []
        : (await sql<{ user_id: string }[]>`
            select user_id
            from public.fight_members
            where fight_id = ${fightId}
              and user_id in ${sql(wantedTags)}
              and state in ('accepted', 'deferred')
          `).map((row) => row.user_id);
      ids.push(await insertFightPost(userId, "fight", fightId, input.body, mediaIds, fightTags, sql));
    }
    return ids;
  });

  return { posts: await mapPosts(userId, await loadPostRows(createdIds, database), database) };
}

export async function listFeedPeople(
  userId: string,
  query: ListFeedPeopleQuery,
  database: Sql = createDatabaseClient(),
): Promise<FeedPeopleResponse> {
  const fightIds = (query.fight_ids ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  for (const fightId of fightIds) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(fightId)) {
      throw new ApiError(400, ERROR_CODES.validation, "fight_ids must be UUID v4 values");
    }
    await requireRosterMember(userId, fightId, database);
  }
  const includeMain = query.main === "true" || query.main === "1";
  if (!includeMain && fightIds.length === 0) {
    return { people: [] };
  }

  const rows = await database<(MediaRow & {
    user_id: string;
    handle: string;
    display_name: string;
    avatar_id: string | null;
    avatar_kind: MediaRow["kind"] | null;
    avatar_purpose: MediaRow["purpose"] | null;
    avatar_status: MediaRow["status"] | null;
    avatar_object_path: string | null;
    avatar_original_filename: string | null;
    avatar_content_type: MediaRow["content_type"] | null;
    avatar_byte_size: string | number | null;
    avatar_width: number | null;
    avatar_height: number | null;
    avatar_duration_ms: number | null;
    avatar_sha256: string | null;
    avatar_created_at: Date | string | null;
  })[]>`
    select distinct
      profile.user_id, profile.handle, profile.display_name,
      avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
      avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
      avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
      avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
      avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
      avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
    from public.profiles as profile
    left join public.media_objects as avatar
      on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
    where profile.deleted_at is null
      and profile.user_id <> ${userId}
      and not exists (
        select 1 from private.feed_blocks as blocked
        where (blocked.blocker_id = ${userId} and blocked.blocked_id = profile.user_id)
           or (blocked.blocker_id = profile.user_id and blocked.blocked_id = ${userId})
      )
      and (
        (
          ${includeMain}::boolean
          and exists (
            select 1
            from public.fight_members as me
            join public.fight_members as them
              on them.fight_id = me.fight_id
            where me.user_id = ${userId}
              and them.user_id = profile.user_id
              and me.state in ('accepted', 'deferred')
              and them.state in ('accepted', 'deferred')
          )
        )
        or (
          ${fightIds.length > 0}::boolean
          and exists (
            select 1
            from public.fight_members as membership
            where membership.user_id = profile.user_id
              and membership.state in ('accepted', 'deferred')
              and membership.fight_id in ${database(fightIds.length > 0 ? fightIds : [userId])}
          )
        )
      )
    order by profile.handle
    limit 80
  `;

  const people = [];
  for (const row of rows) {
    let avatar = null;
    if (row.avatar_id && row.avatar_kind && row.avatar_purpose && row.avatar_status
      && row.avatar_object_path && row.avatar_original_filename && row.avatar_content_type
      && row.avatar_byte_size !== null && row.avatar_width !== null && row.avatar_height !== null
      && row.avatar_sha256 && row.avatar_created_at) {
      avatar = mapMedia({
        id: row.avatar_id,
        owner_id: row.user_id,
        kind: row.avatar_kind,
        purpose: row.avatar_purpose,
        status: row.avatar_status,
        object_path: row.avatar_object_path,
        original_filename: row.avatar_original_filename,
        content_type: row.avatar_content_type,
        byte_size: row.avatar_byte_size,
        width: row.avatar_width,
        height: row.avatar_height,
        duration_ms: row.avatar_duration_ms,
        sha256: row.avatar_sha256,
        created_at: row.avatar_created_at,
      }, await signMediaUrl(row.avatar_object_path));
    }
    people.push({
      user_id: row.user_id,
      handle: row.handle,
      display_name: row.display_name,
      avatar,
    });
  }
  return { people };
}

export async function deleteFightPost(
  userId: string,
  fightId: string | undefined,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  const post = await loadVisiblePost(userId, postId, database);
  if (post.author_id !== userId) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
  if (fightId && post.fight_id !== fightId) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
  const [deleted] = await database<{ id: string }[]>`
    delete from public.fight_posts
    where id = ${postId}
      and author_id = ${userId}
    returning id
  `;
  if (!deleted) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
}

export async function reportFightPost(
  userId: string,
  fightId: string | undefined,
  postId: string,
  input: ReportFightPostRequest,
  database: Sql = createDatabaseClient(),
): Promise<ReportFightPostResponse> {
  const post = await loadVisiblePost(userId, postId, database);
  if (fightId && post.fight_id !== fightId) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
  if (post.author_id === userId) {
    throw new ApiError(400, ERROR_CODES.validation, "You cannot report your own post");
  }
  await database`
    insert into private.fight_post_reports (post_id, reporter_id, reason)
    values (${postId}, ${userId}, ${input.reason})
    on conflict (post_id, reporter_id) do update set reason = excluded.reason
  `;
  return { reported: true };
}

export async function blockFeedAuthor(
  userId: string,
  blockedId: string,
  database: Sql = createDatabaseClient(),
): Promise<BlockFeedAuthorResponse> {
  if (userId === blockedId) {
    throw new ApiError(400, ERROR_CODES.validation, "You cannot hide yourself");
  }
  const [profile] = await database<{ user_id: string }[]>`
    select user_id from public.profiles
    where user_id = ${blockedId} and deleted_at is null
  `;
  if (!profile) {
    throw new ApiError(404, ERROR_CODES.not_found, "That person is not on FitFight");
  }
  await database`
    insert into private.feed_blocks (blocker_id, blocked_id)
    values (${userId}, ${blockedId})
    on conflict (blocker_id, blocked_id) do nothing
  `;
  return { blocked: true };
}

export async function listPostReactions(
  userId: string,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<FightPostReaction[]> {
  const rows = await database<ReactionRow[]>`
    select
      reaction.post_id,
      reaction.emoji,
      count(*)::int as count,
      bool_or(reaction.user_id = ${userId}) as mine
    from public.fight_post_reactions as reaction
    where reaction.post_id = ${postId}
    group by reaction.post_id, reaction.emoji
    order by count(*) desc, reaction.emoji
  `;
  return rows.map((row) => ({ emoji: row.emoji, count: row.count, mine: row.mine }));
}
