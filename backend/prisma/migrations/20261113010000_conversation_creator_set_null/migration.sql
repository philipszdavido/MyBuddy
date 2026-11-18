-- Deleting an account must not delete conversations it created (the other participants keep them).
ALTER TABLE "conversations" DROP CONSTRAINT "conversations_created_by_id_fkey";
ALTER TABLE "conversations" ALTER COLUMN "created_by_id" DROP NOT NULL;
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_created_by_id_fkey"
  FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
