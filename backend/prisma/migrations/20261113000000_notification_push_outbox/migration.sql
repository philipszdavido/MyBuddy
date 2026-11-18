-- Outbox marker for push delivery (see NotificationWriter / notification sweeper).
ALTER TABLE "notifications" ADD COLUMN "push_processed_at" TIMESTAMP(3);
CREATE INDEX "notifications_push_processed_at_created_at_idx" ON "notifications"("push_processed_at", "created_at");
