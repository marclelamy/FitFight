import type { Sql } from "postgres";
import { revokeAppleRefreshToken } from "@/lib/apple/apple-sign-in";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readStoredAppleRefreshToken } from "./apple-sign-in-supabase-query";
import { removeStoragePaths } from "./media-supabase-query";
import { removeProviderInboxObjects } from "./provider-uploads-supabase-query";

/** Remove the account and its owned fights, including fights with other participants. */
export async function deleteAccount(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<boolean> {
  try {
    let appleRefreshToken: string | null = null;
    try {
      appleRefreshToken = await readStoredAppleRefreshToken(userId, database);
    } catch (error) {
      console.error(
        "apple_authorization_read_failed",
        error instanceof Error ? error.name : "unknown",
      );
    }

    await removeProviderInboxObjects(userId, database);
    const mediaPaths = await database.begin("read write", async (sql) => {
      const [profile] = await sql<{ user_id: string }[]>`
        select user_id from public.profiles
        where user_id = ${userId} and deleted_at is null
        for update
      `;
      if (!profile) {
        throw new ApiError(404, ERROR_CODES.not_found, "Account not found");
      }
      const media = await sql<{ object_path: string }[]>`
        select object_path from public.media_objects where owner_id = ${userId} for update
      `;

      await sql`delete from public.feedback_votes where user_id = ${userId}`;
      await sql`delete from public.feedback_comments where author_id = ${userId}`;
      await sql`delete from public.feedback_posts where author_id = ${userId}`;
      await sql`delete from private.fight_post_reports where reporter_id = ${userId}`;
      await sql`delete from private.fight_post_comment_reports where reporter_id = ${userId}`;
      await sql`delete from private.feed_blocks where blocker_id = ${userId} or blocked_id = ${userId}`;
      await sql`delete from public.fight_post_comments where author_id = ${userId}`;
      await sql`delete from public.fight_post_reactions where user_id = ${userId}`;
      await sql`delete from public.fight_post_tags where user_id = ${userId}`;
      await sql`delete from public.fight_posts where author_id = ${userId}`;
      await sql`delete from public.media_objects where owner_id = ${userId}`;

      await sql`
        update public.fight_series
        set paused_at = coalesce(paused_at, now())
        where owner_id = ${userId}
      `;

      await sql`delete from public.fights where owner_id = ${userId}`;
      await sql`delete from public.fight_series where owner_id = ${userId}`;
      await sql`delete from public.fight_series_members where user_id = ${userId}`;
      await sql`delete from private.fight_score_snapshots where user_id = ${userId}`;
      await sql`delete from private.metric_observations where user_id = ${userId}`;
      await sql`delete from private.provider_events where user_id = ${userId}`;
      await sql`delete from private.provider_uploads where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_source_days where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_sample_deletions where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_samples where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_syncs where user_id = ${userId}`;
      await sql`delete from public.metric_days where user_id = ${userId}`;
      await sql`delete from public.step_days where user_id = ${userId}`;
      await sql`delete from public.fight_members where user_id = ${userId}`;
      await sql`delete from public.fight_invites where invited_user_id = ${userId}`;
      await sql`
        delete from public.friendships
        where requester_id = ${userId} or addressee_id = ${userId}
      `;
      await sql`delete from public.data_sources where user_id = ${userId}`;
      await sql`delete from private.fight_join_attempts where user_id = ${userId}`;
      await sql`delete from auth.sessions where user_id = ${userId}`;
      await sql`delete from auth.refresh_tokens where user_id = ${userId}`;
      await sql`delete from auth.identities where user_id = ${userId}`;

      await sql`delete from auth.users where id = ${userId}`;
      return media.map((row) => row.object_path);
    });
    try {
      await removeStoragePaths(mediaPaths);
    } catch (error) {
      console.error(
        "user_media_remove_failed",
        error instanceof Error ? error.name : "unknown",
      );
    }

    if (!appleRefreshToken) {
      return false;
    }
    try {
      await revokeAppleRefreshToken(appleRefreshToken);
      return true;
    } catch (error) {
      console.error(
        "apple_authorization_revoke_failed",
        error instanceof Error ? error.name : "unknown",
      );
      return false;
    }
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    console.error("account_delete_failed", error instanceof Error ? error.name : "unknown");
    throw new ApiError(500, ERROR_CODES.db_error, "Could not delete account");
  }
}
