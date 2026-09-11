import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  BlockFeedbackAuthorResponse,
  CreateFeedbackCommentRequest,
  CreateFeedbackPostRequest,
  FeedbackComment,
  FeedbackCommentResponse,
  FeedbackKind,
  FeedbackListResponse,
  FeedbackPostDetail,
  FeedbackPostResponse,
  FeedbackPostSummary,
  FeedbackVoteResponse,
  ListFeedbackQuery,
  ReportFeedbackPostRequest,
  ReportFeedbackPostResponse,
} from "@/lib/types/feedback/feedback";

const POST_LIMIT_PER_DAY = 8;
const COMMENT_LIMIT_PER_DAY = 30;

type FeedbackPostRow = {
  id: string;
  kind: FeedbackKind;
  title: string;
  body: string;
  vote_count: number;
  comment_count: number;
  voted: boolean;
  author_id: string;
  author_handle: string;
  mine: boolean;
  created_at: Date | string;
};

type FeedbackCommentRow = {
  id: string;
  body: string;
  author_handle: string;
  created_at: Date | string;
};

function isoUtc(value: Date | string): string {
  return new Date(value).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function mapPost(row: FeedbackPostRow): FeedbackPostSummary {
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    body: row.body,
    vote_count: row.vote_count,
    comment_count: row.comment_count,
    voted: row.voted,
    author_id: row.author_id,
    author_handle: row.author_handle,
    mine: row.mine,
    created_at: isoUtc(row.created_at),
  };
}

function mapComment(row: FeedbackCommentRow): FeedbackComment {
  return {
    id: row.id,
    body: row.body,
    author_handle: row.author_handle,
    created_at: isoUtc(row.created_at),
  };
}

export async function listFeedbackPosts(
  userId: string,
  query: ListFeedbackQuery,
  database: Sql = createDatabaseClient(),
): Promise<FeedbackListResponse> {
  const kind = query.kind ?? null;
  const rows = await database<FeedbackPostRow[]>`
    select
      post.id,
      post.kind::text as kind,
      post.title,
      post.body,
      (
        select count(*)::int
        from public.feedback_votes as vote
        where vote.post_id = post.id
      ) as vote_count,
      (
        select count(*)::int
        from public.feedback_comments as comment
        where comment.post_id = post.id
      ) as comment_count,
      exists(
        select 1
        from public.feedback_votes as vote
        where vote.post_id = post.id
          and vote.user_id = ${userId}
      ) as voted,
      post.author_id,
      profile.handle as author_handle,
      post.author_id = ${userId} as mine,
      post.created_at
    from public.feedback_posts as post
    join public.profiles as profile
      on profile.user_id = post.author_id
     and profile.deleted_at is null
    where (${kind}::text is null or post.kind::text = ${kind})
      and not exists (
        select 1 from private.feedback_blocks as blocked
        where blocked.blocker_id = ${userId}
          and blocked.blocked_id = post.author_id
      )
    order by vote_count desc, post.created_at desc
    limit 100
  `;
  return { posts: rows.map(mapPost) };
}

export async function getFeedbackPost(
  userId: string,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<FeedbackPostDetail> {
  const [row] = await database<FeedbackPostRow[]>`
    select
      post.id,
      post.kind::text as kind,
      post.title,
      post.body,
      (
        select count(*)::int
        from public.feedback_votes as vote
        where vote.post_id = post.id
      ) as vote_count,
      (
        select count(*)::int
        from public.feedback_comments as comment
        where comment.post_id = post.id
      ) as comment_count,
      exists(
        select 1
        from public.feedback_votes as vote
        where vote.post_id = post.id
          and vote.user_id = ${userId}
      ) as voted,
      post.author_id,
      profile.handle as author_handle,
      post.author_id = ${userId} as mine,
      post.created_at
    from public.feedback_posts as post
    join public.profiles as profile
      on profile.user_id = post.author_id
     and profile.deleted_at is null
    where post.id = ${postId}
      and not exists (
        select 1 from private.feedback_blocks as blocked
        where blocked.blocker_id = ${userId}
          and blocked.blocked_id = post.author_id
      )
  `;
  if (!row) {
    throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
  }
  const comments = await database<FeedbackCommentRow[]>`
    select
      comment.id,
      comment.body,
      profile.handle as author_handle,
      comment.created_at
    from public.feedback_comments as comment
    join public.profiles as profile
      on profile.user_id = comment.author_id
     and profile.deleted_at is null
    where comment.post_id = ${postId}
      and not exists (
        select 1 from private.feedback_blocks as blocked
        where blocked.blocker_id = ${userId}
          and blocked.blocked_id = comment.author_id
      )
    order by comment.created_at
  `;
  return { post: mapPost(row), comments: comments.map(mapComment) };
}

export async function createFeedbackPost(
  userId: string,
  input: CreateFeedbackPostRequest,
  database: Sql = createDatabaseClient(),
): Promise<FeedbackPostResponse> {
  const [rate] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.feedback_posts
    where author_id = ${userId}
      and created_at > now() - interval '24 hours'
  `;
  if ((rate?.n ?? 0) >= POST_LIMIT_PER_DAY) {
    throw new ApiError(
      429,
      ERROR_CODES.rate_limited,
      "You’ve posted a few times recently. Try again later.",
    );
  }

  const [row] = await database<FeedbackPostRow[]>`
    insert into public.feedback_posts (author_id, kind, title, body)
    values (
      ${userId},
      ${input.kind}::public.feedback_kind,
      ${input.title},
      ${input.body}
    )
    returning
      id,
      kind::text as kind,
      title,
      body,
      0 as vote_count,
      0 as comment_count,
      false as voted,
      ${userId} as author_id,
      (
        select handle
        from public.profiles
        where user_id = ${userId}
          and deleted_at is null
      ) as author_handle,
      true as mine,
      created_at
  `;
  if (!row?.author_handle) {
    throw new ApiError(400, ERROR_CODES.profile_missing, "Profile is missing");
  }
  return { post: mapPost(row) };
}

export async function toggleFeedbackVote(
  userId: string,
  postId: string,
  database: Sql = createDatabaseClient(),
): Promise<FeedbackVoteResponse> {
  return database.begin("read write", async (sql) => {
    const [post] = await sql<{ id: string }[]>`
      select id from public.feedback_posts where id = ${postId}
    `;
    if (!post) {
      throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }

    const deleted = await sql<{ post_id: string }[]>`
      delete from public.feedback_votes
      where post_id = ${postId} and user_id = ${userId}
      returning post_id
    `;
    let voted = false;
    if (deleted.length === 0) {
      await sql`
        insert into public.feedback_votes (post_id, user_id)
        values (${postId}, ${userId})
        on conflict (post_id, user_id) do nothing
      `;
      voted = true;
    }
    const [counts] = await sql<{ vote_count: number }[]>`
      select count(*)::int as vote_count
      from public.feedback_votes
      where post_id = ${postId}
    `;
    return { voted, vote_count: counts?.vote_count ?? 0 };
  });
}

export async function createFeedbackComment(
  userId: string,
  postId: string,
  input: CreateFeedbackCommentRequest,
  database: Sql = createDatabaseClient(),
): Promise<FeedbackCommentResponse> {
  const [rate] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.feedback_comments
    where author_id = ${userId}
      and created_at > now() - interval '24 hours'
  `;
  if ((rate?.n ?? 0) >= COMMENT_LIMIT_PER_DAY) {
    throw new ApiError(
      429,
      ERROR_CODES.rate_limited,
      "You’ve commented a few times recently. Try again later.",
    );
  }

  const [comment] = await database<FeedbackCommentRow[]>`
    insert into public.feedback_comments (post_id, author_id, body)
    select ${postId}, ${userId}, ${input.body}
    where exists (
      select 1 from public.feedback_posts where id = ${postId}
    )
    returning
      id,
      body,
      (
        select handle
        from public.profiles
        where user_id = ${userId}
          and deleted_at is null
      ) as author_handle,
      created_at
  `;
  if (!comment) {
    throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
  }
  if (!comment.author_handle) {
    throw new ApiError(400, ERROR_CODES.profile_missing, "Profile is missing");
  }
  return { comment: mapComment(comment) };
}

export async function reportFeedbackPost(
  userId: string,
  postId: string,
  input: ReportFeedbackPostRequest,
  database: Sql = createDatabaseClient(),
): Promise<ReportFeedbackPostResponse> {
  const [post] = await database<{ id: string; author_id: string }[]>`
    select post.id, post.author_id
    from public.feedback_posts as post
    join public.profiles as profile
      on profile.user_id = post.author_id
     and profile.deleted_at is null
    where post.id = ${postId}
      and not exists (
        select 1 from private.feedback_blocks as blocked
        where blocked.blocker_id = ${userId}
          and blocked.blocked_id = post.author_id
      )
  `;
  if (!post) {
    throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
  }
  if (post.author_id === userId) {
    throw new ApiError(400, ERROR_CODES.validation, "You cannot report your own post");
  }
  await database`
    insert into private.feedback_post_reports (post_id, reporter_id, reason)
    values (${postId}, ${userId}, ${input.reason})
    on conflict (post_id, reporter_id) do update set reason = excluded.reason
  `;
  return { reported: true };
}

export async function blockFeedbackAuthor(
  userId: string,
  blockedId: string,
  database: Sql = createDatabaseClient(),
): Promise<BlockFeedbackAuthorResponse> {
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
    insert into private.feedback_blocks (blocker_id, blocked_id)
    values (${userId}, ${blockedId})
    on conflict (blocker_id, blocked_id) do nothing
  `;
  return { blocked: true };
}
