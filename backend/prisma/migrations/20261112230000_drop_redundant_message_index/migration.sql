-- Duplicates the unique index on (conversation_id, seq).
DROP INDEX IF EXISTS "messages_conversation_seq_live_idx";
