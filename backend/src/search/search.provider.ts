import { Inject, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type Redis from 'ioredis';
import { RelationshipService } from '../graph/relationship.service';
import { PrismaService } from '../prisma/prisma.service';
import { REDIS } from '../redis/redis.module';

export interface SearchPage<T> {
  ids: T[];
  /** Offset for relevance-ranked results; the controller wraps it into an opaque cursor. */
  nextOffset: number | null;
}

export interface PostSearchFilters {
  authorId?: string;
  hashtag?: string;
  hasMedia?: boolean;
  since?: Date;
  sort: 'relevance' | 'recent';
}

export interface HashtagHit {
  tag: string;
  postCount: number;
}

/**
 * Search backend contract. PostgreSQL implements it today (full-text + trigram indexes from the init
 * migration). An OpenSearch implementation can be bound to this token later; it must apply the same
 * privacy rules (visibility, blocks, discoverability), which is why results are ids that the caller
 * re-checks and presents.
 */
export abstract class SearchProvider {
  abstract users(viewerId: string, q: string, offset: number, limit: number): Promise<SearchPage<string>>;
  abstract posts(viewerId: string, q: string, filters: PostSearchFilters, offset: number, limit: number): Promise<SearchPage<string>>;
  abstract hashtags(q: string, limit: number): Promise<HashtagHit[]>;
  abstract trendingHashtags(limit: number): Promise<HashtagHit[]>;
}

export const MAX_SEARCH_RESULTS = 200;
export const TRENDING_KEY = 'search:trending-hashtags';

/** Escapes LIKE wildcards in user input. */
const likeEscape = (s: string) => s.replace(/[\\%_]/g, (c) => `\\${c}`);

@Injectable()
export class PostgresSearchProvider extends SearchProvider {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {
    super();
  }

  async users(viewerId: string, q: string, offset: number, limit: number): Promise<SearchPage<string>> {
    const term = q.replace(/^@/, '').trim().toLowerCase();
    if (!term) return { ids: [], nextOffset: null };
    const prefix = `${likeEscape(term)}%`;
    // Usernames are short, so one typo drops trigram similarity below pg_trgm's 0.3 default; 0.25 keeps
    // single-typo matches. set_config(..., true) is transaction-local, and `%` still uses the GIN index.
    const [, rows] = await this.prisma.$transaction([
      this.prisma.$executeRaw`SELECT set_config('pg_trgm.similarity_threshold', '0.25', true)`,
      this.prisma.$queryRaw<Array<{ user_id: string }>>`
      SELECT up.user_id FROM user_profiles up
      JOIN users u ON u.id = up.user_id AND u.status = 'ACTIVE'
      JOIN user_settings s ON s.user_id = up.user_id
      WHERE up.user_id <> ${viewerId}::uuid
        AND (s.discoverable OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${viewerId}::uuid AND f.followee_id = up.user_id)
             OR EXISTS (SELECT 1 FROM contact_links c WHERE c.owner_id = ${viewerId}::uuid AND c.contact_id = up.user_id))
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`up.user_id`, viewerId)}
        AND (up.username LIKE ${prefix} OR lower(up.display_name) LIKE ${prefix}
             OR up.username % ${term} OR up.display_name % ${term}
             OR up.search_vector @@ plainto_tsquery('simple', ${term}))
      ORDER BY
        (up.username = ${term}) DESC,
        (up.username LIKE ${prefix}) DESC,
        EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${viewerId}::uuid AND f.followee_id = up.user_id) DESC,
        greatest(similarity(coalesce(up.username, ''), ${term}), similarity(up.display_name, ${term})) DESC,
        up.followers_count DESC, up.user_id
      OFFSET ${offset} LIMIT ${limit + 1}`,
    ]);
    return page(rows.map((r) => r.user_id), offset, limit);
  }

  async posts(viewerId: string, q: string, f: PostSearchFilters, offset: number, limit: number): Promise<SearchPage<string>> {
    const text = q.trim();
    const conditions: Prisma.Sql[] = [this.relationships.visiblePostSql(viewerId)];
    if (text) conditions.push(Prisma.sql`p.search_vector @@ websearch_to_tsquery('simple', ${text})`);
    if (f.authorId) conditions.push(Prisma.sql`p.author_id = ${f.authorId}::uuid`);
    if (f.since) conditions.push(Prisma.sql`p.published_at >= ${f.since}`);
    if (f.hasMedia) conditions.push(Prisma.sql`EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id)`);
    if (f.hashtag) {
      conditions.push(Prisma.sql`EXISTS (SELECT 1 FROM post_hashtags ph JOIN hashtags h ON h.id = ph.hashtag_id WHERE ph.post_id = p.id AND h.tag = ${f.hashtag.toLowerCase()})`);
    }
    if (!text && !f.hashtag && !f.authorId) return { ids: [], nextOffset: null };
    // Search only surfaces public posts and posts from people the viewer is connected to (visibility check above).
    const order = f.sort === 'recent' || !text
      ? Prisma.sql`p.published_at DESC, p.id`
      : Prisma.sql`ts_rank(p.search_vector, websearch_to_tsquery('simple', ${text})) * (1 + ln(1 + p.like_count + 2 * p.comment_count)) DESC, p.published_at DESC, p.id`;
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>`
      SELECT p.id FROM posts p
      WHERE p.repost_of_id IS NULL AND ${Prisma.join(conditions, ' AND ')}
      ORDER BY ${order}
      OFFSET ${offset} LIMIT ${limit + 1}`;
    return page(rows.map((r) => r.id), offset, limit);
  }

  async hashtags(q: string, limit: number): Promise<HashtagHit[]> {
    const term = q.replace(/^#/, '').trim().toLowerCase();
    if (!term) return [];
    return this.prisma.$queryRaw<HashtagHit[]>`
      SELECT tag, post_count AS "postCount" FROM hashtags
      WHERE post_count > 0 AND (tag LIKE ${`${likeEscape(term)}%`} OR tag % ${term})
      ORDER BY (tag = ${term}) DESC, (tag LIKE ${`${likeEscape(term)}%`}) DESC, post_count DESC, tag
      LIMIT ${limit}`;
  }

  async trendingHashtags(limit: number): Promise<HashtagHit[]> {
    const cached = await this.redis.get(TRENDING_KEY).catch(() => null);
    if (cached) return (JSON.parse(cached) as HashtagHit[]).slice(0, limit);
    return this.prisma.hashtag.findMany({ where: { postCount: { gt: 0 } }, orderBy: [{ postCount: 'desc' }, { tag: 'asc' }], take: limit, select: { tag: true, postCount: true } });
  }

  /** Recomputed by the search-index queue: hashtags weighted by recent use (last 24h, decayed). */
  async refreshTrending(): Promise<number> {
    const rows = await this.prisma.$queryRaw<HashtagHit[]>`
      SELECT h.tag, h.post_count AS "postCount"
      FROM post_hashtags ph
      JOIN hashtags h ON h.id = ph.hashtag_id
      JOIN posts p ON p.id = ph.post_id AND p.deleted_at IS NULL AND p.status = 'PUBLISHED' AND p.audience = 'PUBLIC'
      WHERE ph.created_at > now() - interval '24 hours'
      GROUP BY h.id
      ORDER BY sum(exp(-extract(epoch FROM now() - ph.created_at) / 21600.0)) DESC, h.post_count DESC
      LIMIT 50`;
    await this.redis.set(TRENDING_KEY, JSON.stringify(rows), 'EX', 3600);
    return rows.length;
  }
}

function page(ids: string[], offset: number, limit: number): SearchPage<string> {
  const hasMore = ids.length > limit && offset + limit < MAX_SEARCH_RESULTS;
  return { ids: ids.slice(0, limit), nextOffset: hasMore ? offset + limit : null };
}
