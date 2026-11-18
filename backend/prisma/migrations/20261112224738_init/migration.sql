-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('USER', 'MODERATOR', 'ADMIN');

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'DELETING');

-- CreateEnum
CREATE TYPE "AccountVisibility" AS ENUM ('PUBLIC', 'PRIVATE');

-- CreateEnum
CREATE TYPE "MessagePermission" AS ENUM ('EVERYONE', 'CONNECTIONS', 'NOBODY');

-- CreateEnum
CREATE TYPE "FollowRequestStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

-- CreateEnum
CREATE TYPE "PostAudience" AS ENUM ('PUBLIC', 'FOLLOWERS', 'CONTACTS');

-- CreateEnum
CREATE TYPE "PostStatus" AS ENUM ('DRAFT', 'PUBLISHED');

-- CreateEnum
CREATE TYPE "ReactionType" AS ENUM ('LIKE', 'DISLIKE');

-- CreateEnum
CREATE TYPE "FeedReason" AS ENUM ('SELF', 'FOLLOW', 'CONTACT');

-- CreateEnum
CREATE TYPE "MediaKind" AS ENUM ('IMAGE', 'VIDEO');

-- CreateEnum
CREATE TYPE "MediaPurpose" AS ENUM ('AVATAR', 'COVER', 'POST', 'MESSAGE');

-- CreateEnum
CREATE TYPE "MediaStatus" AS ENUM ('PENDING_UPLOAD', 'PROCESSING', 'READY', 'FAILED');

-- CreateEnum
CREATE TYPE "ConversationKind" AS ENUM ('DIRECT', 'GROUP');

-- CreateEnum
CREATE TYPE "ParticipantRole" AS ENUM ('MEMBER', 'ADMIN');

-- CreateEnum
CREATE TYPE "MessageType" AS ENUM ('TEXT', 'IMAGE', 'VIDEO', 'SYSTEM');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('FOLLOW', 'FOLLOW_REQUEST', 'FOLLOW_ACCEPTED', 'POST_REACTION', 'COMMENT', 'COMMENT_REPLY', 'COMMENT_REACTION', 'MENTION', 'REPOST', 'MESSAGE', 'MESSAGE_REQUEST');

-- CreateEnum
CREATE TYPE "DeliveryStatus" AS ENUM ('PENDING', 'SENT', 'FAILED', 'SKIPPED');

-- CreateEnum
CREATE TYPE "ReportTargetType" AS ENUM ('USER', 'POST', 'COMMENT', 'MESSAGE');

-- CreateEnum
CREATE TYPE "ReportReason" AS ENUM ('SPAM', 'HARASSMENT', 'INAPPROPRIATE', 'IMPERSONATION', 'OTHER');

-- CreateEnum
CREATE TYPE "ReportStatus" AS ENUM ('OPEN', 'REVIEWING', 'ACTIONED', 'DISMISSED');

-- CreateEnum
CREATE TYPE "ModerationActionType" AS ENUM ('DISMISS_REPORT', 'REMOVE_POST', 'REMOVE_COMMENT', 'REMOVE_MESSAGE', 'SUSPEND_USER', 'RESTORE_USER');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "firebase_uid" TEXT NOT NULL,
    "email" TEXT,
    "email_verified" BOOLEAN NOT NULL DEFAULT false,
    "phone_number" TEXT,
    "phone_verified" BOOLEAN NOT NULL DEFAULT false,
    "role" "UserRole" NOT NULL DEFAULT 'USER',
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "last_active_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_profiles" (
    "user_id" UUID NOT NULL,
    "username" TEXT,
    "display_name" TEXT NOT NULL,
    "bio" TEXT,
    "location" TEXT,
    "website" TEXT,
    "avatar_media_id" UUID,
    "cover_media_id" UUID,
    "is_verified" BOOLEAN NOT NULL DEFAULT false,
    "visibility" "AccountVisibility" NOT NULL DEFAULT 'PUBLIC',
    "followers_count" INTEGER NOT NULL DEFAULT 0,
    "following_count" INTEGER NOT NULL DEFAULT 0,
    "posts_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "search_vector" tsvector,

    CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "user_settings" (
    "user_id" UUID NOT NULL,
    "show_activity_status" BOOLEAN NOT NULL DEFAULT true,
    "send_read_receipts" BOOLEAN NOT NULL DEFAULT true,
    "allow_messages_from" "MessagePermission" NOT NULL DEFAULT 'EVERYONE',
    "discoverable" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "user_devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "installation_id" TEXT NOT NULL,
    "fcm_token" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "app_version" TEXT,
    "locale" TEXT,
    "last_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_blocks" (
    "blocker_id" UUID NOT NULL,
    "blocked_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("blocker_id","blocked_id")
);

-- CreateTable
CREATE TABLE "user_mutes" (
    "muter_id" UUID NOT NULL,
    "muted_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_mutes_pkey" PRIMARY KEY ("muter_id","muted_id")
);

-- CreateTable
CREATE TABLE "contact_links" (
    "owner_id" UUID NOT NULL,
    "contact_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "contact_links_pkey" PRIMARY KEY ("owner_id","contact_id")
);

-- CreateTable
CREATE TABLE "follows" (
    "follower_id" UUID NOT NULL,
    "followee_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id","followee_id")
);

-- CreateTable
CREATE TABLE "follow_requests" (
    "id" UUID NOT NULL,
    "requester_id" UUID NOT NULL,
    "target_id" UUID NOT NULL,
    "status" "FollowRequestStatus" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "follow_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "media_assets" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "kind" "MediaKind" NOT NULL,
    "purpose" "MediaPurpose" NOT NULL,
    "status" "MediaStatus" NOT NULL DEFAULT 'PENDING_UPLOAD',
    "object_key" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "size_bytes" BIGINT,
    "declared_bytes" BIGINT NOT NULL,
    "width" INTEGER,
    "height" INTEGER,
    "duration_ms" INTEGER,
    "variants" JSONB,
    "blurhash" TEXT,
    "error" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "uploaded_at" TIMESTAMP(3),
    "processed_at" TIMESTAMP(3),
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "media_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "posts" (
    "id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "client_id" TEXT,
    "text" TEXT,
    "audience" "PostAudience" NOT NULL DEFAULT 'CONTACTS',
    "status" "PostStatus" NOT NULL DEFAULT 'PUBLISHED',
    "repost_of_id" UUID,
    "is_pinned" BOOLEAN NOT NULL DEFAULT false,
    "like_count" INTEGER NOT NULL DEFAULT 0,
    "dislike_count" INTEGER NOT NULL DEFAULT 0,
    "comment_count" INTEGER NOT NULL DEFAULT 0,
    "repost_count" INTEGER NOT NULL DEFAULT 0,
    "share_count" INTEGER NOT NULL DEFAULT 0,
    "save_count" INTEGER NOT NULL DEFAULT 0,
    "impression_count" INTEGER NOT NULL DEFAULT 0,
    "published_at" TIMESTAMP(3),
    "edited_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),
    "search_vector" tsvector,

    CONSTRAINT "posts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "post_media" (
    "post_id" UUID NOT NULL,
    "media_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "post_media_pkey" PRIMARY KEY ("post_id","position")
);

-- CreateTable
CREATE TABLE "comments" (
    "id" UUID NOT NULL,
    "post_id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "parent_id" UUID,
    "root_id" UUID,
    "client_id" TEXT,
    "text" TEXT NOT NULL,
    "like_count" INTEGER NOT NULL DEFAULT 0,
    "dislike_count" INTEGER NOT NULL DEFAULT 0,
    "reply_count" INTEGER NOT NULL DEFAULT 0,
    "edited_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "comments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "post_reactions" (
    "post_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "type" "ReactionType" NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "post_reactions_pkey" PRIMARY KEY ("post_id","user_id")
);

-- CreateTable
CREATE TABLE "comment_reactions" (
    "comment_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "type" "ReactionType" NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "comment_reactions_pkey" PRIMARY KEY ("comment_id","user_id")
);

-- CreateTable
CREATE TABLE "hashtags" (
    "id" UUID NOT NULL,
    "tag" TEXT NOT NULL,
    "post_count" INTEGER NOT NULL DEFAULT 0,
    "last_used_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "hashtags_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "post_hashtags" (
    "post_id" UUID NOT NULL,
    "hashtag_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_hashtags_pkey" PRIMARY KEY ("post_id","hashtag_id")
);

-- CreateTable
CREATE TABLE "mentions" (
    "id" UUID NOT NULL,
    "mentioned_user_id" UUID NOT NULL,
    "post_id" UUID,
    "comment_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "mentions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_posts" (
    "user_id" UUID NOT NULL,
    "post_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "saved_posts_pkey" PRIMARY KEY ("user_id","post_id")
);

-- CreateTable
CREATE TABLE "post_shares" (
    "id" UUID NOT NULL,
    "post_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "channel" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_shares_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feed_entries" (
    "user_id" UUID NOT NULL,
    "post_id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "reason" "FeedReason" NOT NULL,
    "sort_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "feed_entries_pkey" PRIMARY KEY ("user_id","post_id")
);

-- CreateTable
CREATE TABLE "conversations" (
    "id" UUID NOT NULL,
    "kind" "ConversationKind" NOT NULL,
    "direct_key" TEXT,
    "title" TEXT,
    "created_by_id" UUID NOT NULL,
    "last_seq" INTEGER NOT NULL DEFAULT 0,
    "last_message_id" UUID,
    "last_message_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "conversation_participants" (
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "ParticipantRole" NOT NULL DEFAULT 'MEMBER',
    "is_request" BOOLEAN NOT NULL DEFAULT false,
    "last_read_seq" INTEGER NOT NULL DEFAULT 0,
    "last_delivered_seq" INTEGER NOT NULL DEFAULT 0,
    "last_read_at" TIMESTAMP(3),
    "muted_until" TIMESTAMP(3),
    "archived_at" TIMESTAMP(3),
    "cleared_seq" INTEGER NOT NULL DEFAULT 0,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "left_at" TIMESTAMP(3),

    CONSTRAINT "conversation_participants_pkey" PRIMARY KEY ("conversation_id","user_id")
);

-- CreateTable
CREATE TABLE "messages" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "sender_id" UUID NOT NULL,
    "client_id" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "type" "MessageType" NOT NULL,
    "text" TEXT,
    "reply_to_id" UUID,
    "edited_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "message_attachments" (
    "message_id" UUID NOT NULL,
    "media_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "message_attachments_pkey" PRIMARY KEY ("message_id","position")
);

-- CreateTable
CREATE TABLE "message_reactions" (
    "message_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "emoji" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "message_reactions_pkey" PRIMARY KEY ("message_id","user_id","emoji")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "recipient_id" UUID NOT NULL,
    "actor_id" UUID,
    "type" "NotificationType" NOT NULL,
    "post_id" UUID,
    "comment_id" UUID,
    "conversation_id" UUID,
    "dedupe_key" TEXT NOT NULL,
    "data" JSONB,
    "read_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_preferences" (
    "user_id" UUID NOT NULL,
    "type" "NotificationType" NOT NULL,
    "push" BOOLEAN NOT NULL DEFAULT true,
    "in_app" BOOLEAN NOT NULL DEFAULT true,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id","type")
);

-- CreateTable
CREATE TABLE "notification_deliveries" (
    "id" UUID NOT NULL,
    "notification_id" UUID NOT NULL,
    "device_id" UUID NOT NULL,
    "status" "DeliveryStatus" NOT NULL DEFAULT 'PENDING',
    "error" TEXT,
    "attempted_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reports" (
    "id" UUID NOT NULL,
    "reporter_id" UUID NOT NULL,
    "target_type" "ReportTargetType" NOT NULL,
    "target_user_id" UUID,
    "post_id" UUID,
    "comment_id" UUID,
    "message_id" UUID,
    "reason" "ReportReason" NOT NULL,
    "details" TEXT,
    "status" "ReportStatus" NOT NULL DEFAULT 'OPEN',
    "resolved_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "moderation_actions" (
    "id" UUID NOT NULL,
    "moderator_id" UUID NOT NULL,
    "type" "ModerationActionType" NOT NULL,
    "report_id" UUID,
    "target_user_id" UUID,
    "post_id" UUID,
    "comment_id" UUID,
    "message_id" UUID,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "moderation_actions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" BIGSERIAL NOT NULL,
    "actor_id" UUID,
    "action" TEXT NOT NULL,
    "target_type" TEXT,
    "target_id" TEXT,
    "request_id" TEXT,
    "ip" TEXT,
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recent_searches" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "query" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "recent_searches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "activity_events" (
    "id" BIGSERIAL NOT NULL,
    "user_id" UUID,
    "type" TEXT NOT NULL,
    "entity_id" TEXT,
    "properties" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "activity_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "post_impressions" (
    "post_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "post_impressions_pkey" PRIMARY KEY ("post_id","user_id","day")
);

-- CreateTable
CREATE TABLE "metric_aggregates" (
    "period" TEXT NOT NULL,
    "bucket" DATE NOT NULL,
    "metric" TEXT NOT NULL,
    "dimension" TEXT NOT NULL DEFAULT '',
    "value" DOUBLE PRECISION NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "metric_aggregates_pkey" PRIMARY KEY ("period","bucket","metric","dimension")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_firebase_uid_key" ON "users"("firebase_uid");

-- CreateIndex
CREATE INDEX "users_phone_number_idx" ON "users"("phone_number");

-- CreateIndex
CREATE UNIQUE INDEX "user_profiles_username_key" ON "user_profiles"("username");

-- CreateIndex
CREATE UNIQUE INDEX "user_profiles_avatar_media_id_key" ON "user_profiles"("avatar_media_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_profiles_cover_media_id_key" ON "user_profiles"("cover_media_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_devices_fcm_token_key" ON "user_devices"("fcm_token");

-- CreateIndex
CREATE UNIQUE INDEX "user_devices_user_id_installation_id_key" ON "user_devices"("user_id", "installation_id");

-- CreateIndex
CREATE INDEX "user_blocks_blocked_id_idx" ON "user_blocks"("blocked_id");

-- CreateIndex
CREATE INDEX "user_mutes_muted_id_idx" ON "user_mutes"("muted_id");

-- CreateIndex
CREATE INDEX "contact_links_contact_id_idx" ON "contact_links"("contact_id");

-- CreateIndex
CREATE INDEX "follows_followee_id_created_at_idx" ON "follows"("followee_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "follows_follower_id_created_at_idx" ON "follows"("follower_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "follow_requests_target_id_status_created_at_idx" ON "follow_requests"("target_id", "status", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "follow_requests_requester_id_target_id_key" ON "follow_requests"("requester_id", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "media_assets_object_key_key" ON "media_assets"("object_key");

-- CreateIndex
CREATE INDEX "media_assets_owner_id_created_at_idx" ON "media_assets"("owner_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "media_assets_status_created_at_idx" ON "media_assets"("status", "created_at");

-- CreateIndex
CREATE INDEX "posts_author_id_published_at_idx" ON "posts"("author_id", "published_at" DESC);

-- CreateIndex
CREATE INDEX "posts_audience_published_at_idx" ON "posts"("audience", "published_at" DESC);

-- CreateIndex
CREATE INDEX "posts_repost_of_id_idx" ON "posts"("repost_of_id");

-- CreateIndex
CREATE UNIQUE INDEX "posts_author_id_client_id_key" ON "posts"("author_id", "client_id");

-- CreateIndex
CREATE UNIQUE INDEX "posts_author_id_repost_of_id_key" ON "posts"("author_id", "repost_of_id");

-- CreateIndex
CREATE UNIQUE INDEX "post_media_media_id_key" ON "post_media"("media_id");

-- CreateIndex
CREATE INDEX "comments_post_id_root_id_created_at_idx" ON "comments"("post_id", "root_id", "created_at");

-- CreateIndex
CREATE INDEX "comments_root_id_created_at_idx" ON "comments"("root_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "comments_author_id_client_id_key" ON "comments"("author_id", "client_id");

-- CreateIndex
CREATE INDEX "post_reactions_post_id_type_created_at_idx" ON "post_reactions"("post_id", "type", "created_at" DESC);

-- CreateIndex
CREATE INDEX "post_reactions_user_id_created_at_idx" ON "post_reactions"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "comment_reactions_comment_id_type_idx" ON "comment_reactions"("comment_id", "type");

-- CreateIndex
CREATE UNIQUE INDEX "hashtags_tag_key" ON "hashtags"("tag");

-- CreateIndex
CREATE INDEX "hashtags_post_count_idx" ON "hashtags"("post_count" DESC);

-- CreateIndex
CREATE INDEX "post_hashtags_hashtag_id_created_at_idx" ON "post_hashtags"("hashtag_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "mentions_mentioned_user_id_created_at_idx" ON "mentions"("mentioned_user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "mentions_post_id_mentioned_user_id_key" ON "mentions"("post_id", "mentioned_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "mentions_comment_id_mentioned_user_id_key" ON "mentions"("comment_id", "mentioned_user_id");

-- CreateIndex
CREATE INDEX "saved_posts_user_id_created_at_idx" ON "saved_posts"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "post_shares_post_id_created_at_idx" ON "post_shares"("post_id", "created_at");

-- CreateIndex
CREATE INDEX "feed_entries_user_id_sort_at_post_id_idx" ON "feed_entries"("user_id", "sort_at" DESC, "post_id");

-- CreateIndex
CREATE INDEX "feed_entries_post_id_idx" ON "feed_entries"("post_id");

-- CreateIndex
CREATE INDEX "feed_entries_user_id_author_id_idx" ON "feed_entries"("user_id", "author_id");

-- CreateIndex
CREATE UNIQUE INDEX "conversations_direct_key_key" ON "conversations"("direct_key");

-- CreateIndex
CREATE UNIQUE INDEX "conversations_last_message_id_key" ON "conversations"("last_message_id");

-- CreateIndex
CREATE INDEX "conversation_participants_user_id_left_at_idx" ON "conversation_participants"("user_id", "left_at");

-- CreateIndex
CREATE UNIQUE INDEX "messages_conversation_id_seq_key" ON "messages"("conversation_id", "seq");

-- CreateIndex
CREATE UNIQUE INDEX "messages_sender_id_client_id_key" ON "messages"("sender_id", "client_id");

-- CreateIndex
CREATE UNIQUE INDEX "message_attachments_media_id_key" ON "message_attachments"("media_id");

-- CreateIndex
CREATE INDEX "notifications_recipient_id_created_at_idx" ON "notifications"("recipient_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "notifications_recipient_id_read_at_idx" ON "notifications"("recipient_id", "read_at");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_recipient_id_dedupe_key_key" ON "notifications"("recipient_id", "dedupe_key");

-- CreateIndex
CREATE UNIQUE INDEX "notification_deliveries_notification_id_device_id_key" ON "notification_deliveries"("notification_id", "device_id");

-- CreateIndex
CREATE INDEX "reports_status_created_at_idx" ON "reports"("status", "created_at");

-- CreateIndex
CREATE INDEX "reports_reporter_id_created_at_idx" ON "reports"("reporter_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "moderation_actions_target_user_id_created_at_idx" ON "moderation_actions"("target_user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "audit_logs_actor_id_created_at_idx" ON "audit_logs"("actor_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "audit_logs_action_created_at_idx" ON "audit_logs"("action", "created_at" DESC);

-- CreateIndex
CREATE INDEX "recent_searches_user_id_created_at_idx" ON "recent_searches"("user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "recent_searches_user_id_query_key" ON "recent_searches"("user_id", "query");

-- CreateIndex
CREATE INDEX "activity_events_type_created_at_idx" ON "activity_events"("type", "created_at");

-- CreateIndex
CREATE INDEX "activity_events_user_id_created_at_idx" ON "activity_events"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "post_impressions_day_idx" ON "post_impressions"("day");

-- CreateIndex
CREATE INDEX "metric_aggregates_metric_period_bucket_idx" ON "metric_aggregates"("metric", "period", "bucket");

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_avatar_media_id_fkey" FOREIGN KEY ("avatar_media_id") REFERENCES "media_assets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_cover_media_id_fkey" FOREIGN KEY ("cover_media_id") REFERENCES "media_assets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_settings" ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_devices" ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_mutes" ADD CONSTRAINT "user_mutes_muter_id_fkey" FOREIGN KEY ("muter_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_mutes" ADD CONSTRAINT "user_mutes_muted_id_fkey" FOREIGN KEY ("muted_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contact_links" ADD CONSTRAINT "contact_links_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contact_links" ADD CONSTRAINT "contact_links_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follows" ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follows" ADD CONSTRAINT "follows_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follow_requests" ADD CONSTRAINT "follow_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follow_requests" ADD CONSTRAINT "follow_requests_target_id_fkey" FOREIGN KEY ("target_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "media_assets" ADD CONSTRAINT "media_assets_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "posts" ADD CONSTRAINT "posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "posts" ADD CONSTRAINT "posts_repost_of_id_fkey" FOREIGN KEY ("repost_of_id") REFERENCES "posts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_media" ADD CONSTRAINT "post_media_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_media" ADD CONSTRAINT "post_media_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "media_assets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_reactions" ADD CONSTRAINT "post_reactions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_reactions" ADD CONSTRAINT "post_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comment_reactions" ADD CONSTRAINT "comment_reactions_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comment_reactions" ADD CONSTRAINT "comment_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_hashtags" ADD CONSTRAINT "post_hashtags_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_hashtags" ADD CONSTRAINT "post_hashtags_hashtag_id_fkey" FOREIGN KEY ("hashtag_id") REFERENCES "hashtags"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mentions" ADD CONSTRAINT "mentions_mentioned_user_id_fkey" FOREIGN KEY ("mentioned_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mentions" ADD CONSTRAINT "mentions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mentions" ADD CONSTRAINT "mentions_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_posts" ADD CONSTRAINT "saved_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_posts" ADD CONSTRAINT "saved_posts_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_shares" ADD CONSTRAINT "post_shares_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_shares" ADD CONSTRAINT "post_shares_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feed_entries" ADD CONSTRAINT "feed_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feed_entries" ADD CONSTRAINT "feed_entries_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_last_message_id_fkey" FOREIGN KEY ("last_message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_participants" ADD CONSTRAINT "conversation_participants_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_participants" ADD CONSTRAINT "conversation_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "message_attachments" ADD CONSTRAINT "message_attachments_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "message_attachments" ADD CONSTRAINT "message_attachments_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "media_assets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "message_reactions" ADD CONSTRAINT "message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "message_reactions" ADD CONSTRAINT "message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "notifications"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "user_devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "reports"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recent_searches" ADD CONSTRAINT "recent_searches_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "post_impressions" ADD CONSTRAINT "post_impressions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ─── Hand-written: constraints Prisma cannot express ───────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_trgm;

ALTER TABLE "follows"         ADD CONSTRAINT "follows_no_self"         CHECK ("follower_id" <> "followee_id");
ALTER TABLE "follow_requests" ADD CONSTRAINT "follow_requests_no_self" CHECK ("requester_id" <> "target_id");
ALTER TABLE "user_blocks"     ADD CONSTRAINT "user_blocks_no_self"     CHECK ("blocker_id" <> "blocked_id");
ALTER TABLE "user_mutes"      ADD CONSTRAINT "user_mutes_no_self"      CHECK ("muter_id" <> "muted_id");
ALTER TABLE "contact_links"   ADD CONSTRAINT "contact_links_no_self"   CHECK ("owner_id" <> "contact_id");

ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_username_format"
  CHECK ("username" IS NULL OR "username" ~ '^[a-z0-9_.]{3,30}$');
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_counts_nonneg"
  CHECK ("followers_count" >= 0 AND "following_count" >= 0 AND "posts_count" >= 0);
ALTER TABLE "posts" ADD CONSTRAINT "posts_counts_nonneg"
  CHECK ("like_count" >= 0 AND "dislike_count" >= 0 AND "comment_count" >= 0 AND "repost_count" >= 0
     AND "share_count" >= 0 AND "save_count" >= 0 AND "impression_count" >= 0);
ALTER TABLE "comments" ADD CONSTRAINT "comments_counts_nonneg"
  CHECK ("like_count" >= 0 AND "dislike_count" >= 0 AND "reply_count" >= 0);
ALTER TABLE "hashtags" ADD CONSTRAINT "hashtags_count_nonneg" CHECK ("post_count" >= 0);
ALTER TABLE "mentions" ADD CONSTRAINT "mentions_one_source"
  CHECK (("post_id" IS NOT NULL)::int + ("comment_id" IS NOT NULL)::int = 1);
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_direct_key"
  CHECK (("kind" = 'DIRECT') = ("direct_key" IS NOT NULL));

-- ─── Full-text search (generated tsvector columns; 'simple' config: multilingual, no stemming) ─────
ALTER TABLE "posts" DROP COLUMN IF EXISTS "search_vector";
ALTER TABLE "posts" ADD COLUMN "search_vector" tsvector
  GENERATED ALWAYS AS (to_tsvector('simple', coalesce("text", ''))) STORED;
CREATE INDEX "posts_search_vector_idx" ON "posts" USING GIN ("search_vector");

ALTER TABLE "user_profiles" DROP COLUMN IF EXISTS "search_vector";
ALTER TABLE "user_profiles" ADD COLUMN "search_vector" tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('simple', coalesce("username", '')), 'A') ||
    setweight(to_tsvector('simple', coalesce("display_name", '')), 'B')
  ) STORED;
CREATE INDEX "user_profiles_search_vector_idx" ON "user_profiles" USING GIN ("search_vector");

-- Prefix/fuzzy matching for search suggestions.
CREATE INDEX "user_profiles_username_trgm_idx"     ON "user_profiles" USING GIN ("username" gin_trgm_ops);
CREATE INDEX "user_profiles_display_name_trgm_idx" ON "user_profiles" USING GIN ("display_name" gin_trgm_ops);
CREATE INDEX "hashtags_tag_trgm_idx"               ON "hashtags"      USING GIN ("tag" gin_trgm_ops);

-- Hot partial indexes: live content only.
CREATE INDEX "posts_live_public_idx" ON "posts" ("published_at" DESC)
  WHERE "deleted_at" IS NULL AND "status" = 'PUBLISHED' AND "audience" = 'PUBLIC';
CREATE INDEX "messages_conversation_seq_live_idx" ON "messages" ("conversation_id", "seq" DESC);
CREATE INDEX "notifications_unread_idx" ON "notifications" ("recipient_id") WHERE "read_at" IS NULL;
CREATE INDEX "activity_events_created_brin" ON "activity_events" USING BRIN ("created_at");
CREATE INDEX "media_assets_pending_idx" ON "media_assets" ("created_at") WHERE "status" = 'PENDING_UPLOAD';
