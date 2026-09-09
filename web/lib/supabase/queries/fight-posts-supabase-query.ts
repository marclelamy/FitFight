import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  BlockFeedAuthorResponse,
  CreateFightPostRequest,
  FightPost,
  FightPostListResponse,
  FightPostResponse,
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

type PostRow = {
  id: string;
  fight_id: string;
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
  const attachments = await database<AttachmentRow[]>`
    select
      attachment.post_id,
      media.id, media.owner_id, media.kind::text as kind, media.purpose::text as purpose,
      media.status::text as status, media.object_path, media.original_filename,
      media.content_type, media.byte_size::text, media.width, media.height,
      media.duration_ms, media.sha256, media.created_at
    from public.fight_post_media as attachment
    join public.media_objects as media on media.id = attachment.media_id
    where attachment.post_id in ${database(rows.map((row) => row.id))}
    order by attachment.post_id, attachment.sort, media.id
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

  return rows.map((row) => ({
    id: row.id,
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
  const rows = cursor
    ? await database<PostRow[]>`
        select
          post.id, post.fight_id, fight.name as fight_name, post.body, post.created_at,
          post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_posts as post
        join public.fights as fight on fight.id = post.fight_id
        join public.profiles as profile
          on profile.user_id = post.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        join public.fight_members as membership
          on membership.fight_id = post.fight_id
         and membership.user_id = ${userId}
         and membership.state in ('accepted', 'deferred')
        where (${fightId ?? null}::uuid is null or post.fight_id = ${fightId ?? null})
          and not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = post.author_id
          )
          and (post.created_at, post.id) < (${cursor.createdAt}::timestamptz, ${cursor.id}::uuid)
        order by post.created_at desc, post.id desc
        limit ${query.limit + 1}
      `
    : await database<PostRow[]>`
        select
          post.id, post.fight_id, fight.name as fight_name, post.body, post.created_at,
          post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_posts as post
        join public.fights as fight on fight.id = post.fight_id
        join public.profiles as profile
          on profile.user_id = post.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        join public.fight_members as membership
          on membership.fight_id = post.fight_id
         and membership.user_id = ${userId}
         and membership.state in ('accepted', 'deferred')
        where (${fightId ?? null}::uuid is null or post.fight_id = ${fightId ?? null})
          and not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = post.author_id
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

  const uniqueMediaIds = [...new Set(input.media_ids)];
  const media = await loadReadyMedia(userId, uniqueMediaIds, "fight_post", database);
  if (media.length !== uniqueMediaIds.length) {
    throw new ApiError(400, ERROR_CODES.validation, "Every photo must be one you just uploaded");
  }

  const createdId = await database.begin("read write", async (sql) => {
    if (uniqueMediaIds.length > 0) {
      const [taken] = await sql<{ n: number }[]>`
        select count(*)::int as n
        from public.fight_post_media
        where media_id in ${sql(uniqueMediaIds)}
      `;
      if ((taken?.n ?? 0) > 0) {
        throw new ApiError(409, ERROR_CODES.conflict, "A photo was already used on another post");
      }
    }
    const [created] = await sql<{ id: string }[]>`
      insert into public.fight_posts (fight_id, author_id, body)
      values (${fightId}, ${userId}, ${input.body})
      returning id
    `;
    if (!created) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not save that post");
    }
    for (const [index, mediaId] of uniqueMediaIds.entries()) {
      await sql`
        insert into public.fight_post_media (post_id, media_id, sort)
        values (${created.id}, ${mediaId}, ${index})
      `;
    }
    return created.id;
  });

  const [row] = await database<PostRow[]>`
    select
      post.id, post.fight_id, fight.name as fight_name, post.body, post.created_at,
      post.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
      avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
      avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
      avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
      avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
      avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
      avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
    from public.fight_posts as post
    join public.fights as fight on fight.id = post.fight_id
    join public.profiles as profile
      on profile.user_id = post.author_id and profile.deleted_at is null
    left join public.media_objects as avatar
      on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
    where post.id = ${createdId}
  `;
  if (!row) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that post");
  }
  const [created] = await mapPosts(userId, [row], database);
  if (!created) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that post");
  }
  return { post: created };
}

export async function deleteFightPost(
  userId: string,
  fightId: string,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await requireRosterMember(userId, fightId, database);
  const [deleted] = await database<{ id: string }[]>`
    delete from public.fight_posts
    where id = ${postId}
      and fight_id = ${fightId}
      and author_id = ${userId}
    returning id
  `;
  if (!deleted) {
    throw new ApiError(404, ERROR_CODES.not_found, "Post not found");
  }
}

export async function reportFightPost(
  userId: string,
  fightId: string,
  postId: string,
  input: ReportFightPostRequest,
  database: Sql = createDatabaseClient(),
): Promise<ReportFightPostResponse> {
  await requireRosterMember(userId, fightId, database);
  const [post] = await database<{ id: string; author_id: string }[]>`
    select id, author_id
    from public.fight_posts
    where id = ${postId} and fight_id = ${fightId}
  `;
  if (!post) {
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
