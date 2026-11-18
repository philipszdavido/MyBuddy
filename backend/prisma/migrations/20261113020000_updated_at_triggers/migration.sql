-- Prisma's @updatedAt is client-side only; counters are often changed with raw SQL. These triggers keep
-- updated_at truthful for every write path (the nightly counter reconciliation relies on it).
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER posts_set_updated_at BEFORE UPDATE ON "posts" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER comments_set_updated_at BEFORE UPDATE ON "comments" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER user_profiles_set_updated_at BEFORE UPDATE ON "user_profiles" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
