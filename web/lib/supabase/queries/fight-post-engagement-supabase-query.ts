import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  CreateFightPostCommentRequest,
  FightPostAuthor,
  FightPostComment,
  FightPostCommentListResponse,
  FightPostCommentResponse,
  FightPostReactionResponse,
  ListFightPostCommentsQuery,
  ReportFightPostCommentRequest,
  ReportFightPostCommentResponse,
} from "@/lib/types/feed/fight-post";
import { loadVisiblePost, listPostReactions } from "./fight-posts-supabase-query";
import { mapMedia, signMediaUrl, type MediaRow } from "./media-supabase-query";

const COMMENT_LIMIT_PER_DAY = 40;

type CommentRow = {
  id: string;
  post_id: string;
  parent_id: string | null;
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

function authorFromRow(row: CommentRow, url: string | null): FightPostAuthor {
  if (!row.avatar_id || !row.avatar_kind || !row.avatar_purpose || !row.avatar_status
    || !row.avatar_object_path || !row.avatar_original_filename || !row.avatar_content_type
    || row.avatar_byte_size === null || row.avatar_width === null || row.avatar_height === null
    || !row.avatar_sha256 || !row.avatar_created_at) {
    return {
      user_id: row.author_id,
      handle: row.author_handle,
      display_name: row.author_display_name,
      avatar: null,
    };
  }
  return {
    user_id: row.author_id,
    handle: row.author_handle,
    display_name: row.author_display_name,
    avatar: mapMedia({
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
    }, url),
  };
}

async function mapComments(userId: string, rows: CommentRow[]): Promise<FightPostComment[]> {
  const urls = new Map<string, string | null>();
  for (const row of rows) {
    if (row.avatar_object_path && !urls.has(row.avatar_object_path)) {
      urls.set(row.avatar_object_path, await signMediaUrl(row.avatar_object_path));
    }
  }
  return rows.map((row) => ({
    id: row.id,
    post_id: row.post_id,
    parent_id: row.parent_id,
    body: row.body,
    created_at: isoUtc(row.created_at),
    mine: row.author_id === userId,
    author: authorFromRow(row, row.avatar_object_path ? urls.get(row.avatar_object_path) ?? null : null),
  }));
}

export async function listFightPostComments(
  userId: string,
  postId: string,
  query: ListFightPostCommentsQuery,
  database: Sql = createDatabaseClient(),
): Promise<FightPostCommentListResponse> {
  await loadVisiblePost(userId, postId, database);
  const cursor = parseCursor(query.cursor);
  const rows = cursor
    ? await database<CommentRow[]>`
        select
          comment.id, comment.post_id, comment.parent_id, comment.body, comment.created_at,
          comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_post_comments as comment
        join public.profiles as profile
          on profile.user_id = comment.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where comment.post_id = ${postId}
          and not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
          )
          and (comment.created_at, comment.id) > (${cursor.createdAt}::timestamptz, ${cursor.id}::uuid)
        order by comment.created_at, comment.id
        limit ${query.limit + 1}
      `
    : await database<CommentRow[]>`
        select
          comment.id, comment.post_id, comment.parent_id, comment.body, comment.created_at,
          comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
          avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
          avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
          avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
          avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
          avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
          avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_post_comments as comment
        join public.profiles as profile
          on profile.user_id = comment.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
          on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where comment.post_id = ${postId}
          and not exists (
            select 1 from private.feed_blocks as blocked
            where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
          )
        order by comment.created_at, comment.id
        limit ${query.limit + 1}
      `;
  const page = rows.slice(0, query.limit);
  const last = page.at(-1);
  return {
    comments: await mapComments(userId, page),
    next_cursor: rows.length > query.limit && last
      ? `${cursorStamp(last.created_at)}|${last.id}`
      : null,
  };
}

export async function createFightPostComment(
  userId: string,
  postId: string,
  input: CreateFightPostCommentRequest,
  database: Sql = createDatabaseClient(),
): Promise<FightPostCommentResponse> {
  await loadVisiblePost(userId, postId, database);
  const [rate] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.fight_post_comments
    where author_id = ${userId}
      and created_at > now() - interval '24 hours'
  `;
  if ((rate?.n ?? 0) >= COMMENT_LIMIT_PER_DAY) {
    throw new ApiError(429, ERROR_CODES.rate_limited, "You’ve commented a few times recently. Try again later.");
  }
  if (input.parent_id) {
    const [parent] = await database<{ id: string }[]>`
      select id
      from public.fight_post_comments
      where id = ${input.parent_id} and post_id = ${postId}
    `;
    if (!parent) {
      throw new ApiError(404, ERROR_CODES.not_found, "That comment is gone");
    }
  }
  const [created] = await database<{ id: string }[]>`
    insert into public.fight_post_comments (post_id, parent_id, author_id, body)
    values (${postId}, ${input.parent_id ?? null}, ${userId}, ${input.body})
    returning id
  `;
  if (!created) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not save that comment");
  }
  const [row] = await database<CommentRow[]>`
    select
      comment.id, comment.post_id, comment.parent_id, comment.body, comment.created_at,
      comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
      avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
      avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
      avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
      avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
      avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
      avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
    from public.fight_post_comments as comment
    join public.profiles as profile
      on profile.user_id = comment.author_id and profile.deleted_at is null
    left join public.media_objects as avatar
      on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
    where comment.id = ${created.id}
  `;
  if (!row) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that comment");
  }
  const [comment] = await mapComments(userId, [row]);
  if (!comment) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load that comment");
  }
  return { comment };
}

export async function deleteFightPostComment(
  userId: string,
  postId: string,
  commentId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await loadVisiblePost(userId, postId, database);
  const [deleted] = await database<{ id: string }[]>`
    delete from public.fight_post_comments
    where id = ${commentId}
      and post_id = ${postId}
      and author_id = ${userId}
    returning id
  `;
  if (!deleted) {
    throw new ApiError(404, ERROR_CODES.not_found, "Comment not found");
  }
}

export async function reportFightPostComment(
  userId: string,
  postId: string,
  commentId: string,
  input: ReportFightPostCommentRequest,
  database: Sql = createDatabaseClient(),
): Promise<ReportFightPostCommentResponse> {
  await loadVisiblePost(userId, postId, database);
  const [comment] = await database<{ id: string; author_id: string }[]>`
    select id, author_id
    from public.fight_post_comments
    where id = ${commentId} and post_id = ${postId}
  `;
  if (!comment) {
    throw new ApiError(404, ERROR_CODES.not_found, "Comment not found");
  }
  if (comment.author_id === userId) {
    throw new ApiError(400, ERROR_CODES.validation, "You cannot report your own comment");
  }
  await database`
    insert into private.fight_post_comment_reports (comment_id, reporter_id, reason)
    values (${commentId}, ${userId}, ${input.reason})
    on conflict (comment_id, reporter_id) do update set reason = excluded.reason
  `;
  return { reported: true };
}

export async function setFightPostReaction(
  userId: string,
  postId: string,
  emoji: string,
  database: Sql = createDatabaseClient(),
): Promise<FightPostReactionResponse> {
  await loadVisiblePost(userId, postId, database);
  const [existing] = await database<{ emoji: string }[]>`
    select emoji
    from public.fight_post_reactions
    where post_id = ${postId} and user_id = ${userId}
  `;
  if (existing?.emoji === emoji) {
    await database`
      delete from public.fight_post_reactions
      where post_id = ${postId} and user_id = ${userId}
    `;
  } else {
    await database`
      insert into public.fight_post_reactions (post_id, user_id, emoji)
      values (${postId}, ${userId}, ${emoji})
      on conflict (post_id, user_id) do update
        set emoji = excluded.emoji, created_at = now()
    `;
  }
  return { reactions: await listPostReactions(userId, postId, database) };
}
