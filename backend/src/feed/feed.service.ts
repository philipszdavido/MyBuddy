import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import type Redis from 'ioredis';
import { randomUUID } from 'node:crypto';
import { decodeCursor, encodeCursor, Page, parseTimeCursor, timeCursor } from '../common/pagination/cursor';
import type { Env } from '../config/env';
import { RelationshipService } from '../graph/relationship.service';
import { PostPresenter, PostView } from '../posts/post-presenter.service';
import { PrismaService } from '../prisma/prisma.service';
import { REDIS } from '../redis/redis.module';
import { Candidate, CandidateSource, DISCOVER_WEIGHTS, FOLLOWING_WEIGHTS, rank } from './ranker';

export const followingCacheKey = (userId: string) => `feed:following:${userId}`;
const FIRST_PAGE_TTL = 60;
const DISCOVER_SNAPSHOT_TTL = 15 * 60;
const DISCOVER_POOL = 500;

interface CandidateRow {
  id: string;
  author_id: string;
  sort_at: Date;
  source: CandidateSource;
  like_count: number;
  dislike_count: number;
  comment_count: number;
  repost_count: number;
  repost_of_id: string | null;
  has_media: boolean;
  open_reports: number;
}

/**
 * Feed retrieval. Following feed = materialised feed_entries (fan-out on write) merged with recent posts
 * of followed large accounts (fan-out on read). Each page is a strict time window (keyset cursor), ranked
 * *within* the window, so pages never overlap or skip posts even though they are not purely chronological.
 * The discover feed ranks a pool of recent public posts once and pages through that snapshot.
 */
@Injectable()
export class FeedService {
  private readonly fanoutMax: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly presenter: PostPresenter,
    @Inject(REDIS) private readonly redis: Redis,
    config: ConfigService<Env, true>,
  ) {
    this.fanoutMax = config.get('FEED_FANOUT_MAX_FOLLOWERS', { infer: true });
  }

  async following(viewerId: string, cursor: string | undefined, limit: number): Promise<Page<PostView>> {
    if (!cursor) {
      const cached = await this.redis.get(followingCacheKey(viewerId)).catch(() => null);
      if (cached) {
        const { ids, nextCursor, limit: cachedLimit } = JSON.parse(cached) as { ids: string[]; nextCursor: string | null; limit: number };
        if (cachedLimit === limit) {
          // Re-check visibility: a block/delete since caching must take effect immediately.
          const visible = await this.presenter.visibleIds(viewerId, ids);
          return { items: await this.presenter.present(viewerId, ids.filter((id) => visible.has(id))), nextCursor };
        }
      }
    }

    const c = parseTimeCursor(cursor);
    const before = c ? Prisma.sql`AND (x.sort_at, x.id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty;
    const rows = await this.prisma.$queryRaw<CandidateRow[]>`
      WITH entries AS (
        SELECT fe.post_id AS id, fe.sort_at, fe.reason::text AS source
        FROM feed_entries fe WHERE fe.user_id = ${viewerId}::uuid
        ${c ? Prisma.sql`AND (fe.sort_at, fe.post_id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
        ORDER BY fe.sort_at DESC, fe.post_id DESC LIMIT ${limit * 3}
      ),
      large_authors AS (
        SELECT p.id, p.published_at AS sort_at, 'FOLLOW' AS source
        FROM follows f
        JOIN user_profiles up ON up.user_id = f.followee_id AND up.followers_count > ${this.fanoutMax}
        JOIN posts p ON p.author_id = f.followee_id AND p.published_at > now() - interval '14 days'
        WHERE f.follower_id = ${viewerId}::uuid
        ${c ? Prisma.sql`AND (p.published_at, p.id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
        ORDER BY p.published_at DESC LIMIT ${limit * 3}
      ),
      merged AS (
        SELECT DISTINCT ON (id) id, sort_at, source FROM (SELECT * FROM entries UNION ALL SELECT * FROM large_authors) u
        ORDER BY id, sort_at DESC
      )
      SELECT x.id, p.author_id, x.sort_at, x.source, p.like_count, p.dislike_count, p.comment_count, p.repost_count,
             p.repost_of_id,
             EXISTS(SELECT 1 FROM post_media pm WHERE pm.post_id = p.id) AS has_media,
             (SELECT count(*)::int FROM reports r WHERE r.post_id = p.id AND r.status = 'OPEN') AS open_reports
      FROM merged x JOIN posts p ON p.id = x.id
      WHERE ${this.relationships.visiblePostSql(viewerId)}
        AND NOT EXISTS (SELECT 1 FROM user_mutes m WHERE m.muter_id = ${viewerId}::uuid AND m.muted_id = p.author_id)
        ${before}
      ORDER BY x.sort_at DESC, x.id DESC
      LIMIT ${limit + 1}`;

    const hasMore = rows.length > limit;
    const window = dedupeReposts(hasMore ? rows.slice(0, limit) : rows);
    const last = (hasMore ? rows.slice(0, limit) : rows).at(-1);
    const nextCursor = hasMore && last ? timeCursor(last.sort_at, last.id) : null;

    const ranked = rank(await this.toCandidates(viewerId, window), FOLLOWING_WEIGHTS);
    const ids = ranked.map((r) => r.postId);
    if (!cursor) {
      await this.redis.set(followingCacheKey(viewerId), JSON.stringify({ ids, nextCursor, limit }), 'EX', FIRST_PAGE_TTL).catch(() => undefined);
    }
    return { items: await this.presenter.present(viewerId, ids), nextCursor };
  }

  async discover(viewerId: string, cursor: string | undefined, limit: number): Promise<Page<PostView>> {
    let snapshot: string | undefined;
    let offset = 0;
    if (cursor) {
      const c = decodeCursor<{ s: string; o: number }>(cursor, ['s', 'o']);
      snapshot = String(c.s);
      offset = Number(c.o);
    }
    let ids = snapshot ? await this.loadSnapshot(viewerId, snapshot) : null;
    if (!ids) {
      // Expired or first page: build a fresh snapshot. (Rare duplicates after expiry are acceptable.)
      snapshot = randomUUID();
      ids = await this.buildDiscoverSnapshot(viewerId);
      await this.redis.set(this.snapshotKey(viewerId, snapshot), JSON.stringify(ids), 'EX', DISCOVER_SNAPSHOT_TTL).catch(() => undefined);
      if (cursor) offset = 0;
    }
    const slice = ids.slice(offset, offset + limit);
    const visible = await this.presenter.visibleIds(viewerId, slice);
    const items = await this.presenter.present(viewerId, slice.filter((id) => visible.has(id)));
    const next = offset + limit < ids.length ? encodeCursor({ s: snapshot!, o: offset + limit }) : null;
    return { items, nextCursor: next };
  }

  private snapshotKey(viewerId: string, snapshot: string) {
    return `feed:discover:${viewerId}:${snapshot}`;
  }

  private async loadSnapshot(viewerId: string, snapshot: string): Promise<string[] | null> {
    const raw = await this.redis.get(this.snapshotKey(viewerId, snapshot)).catch(() => null);
    return raw ? (JSON.parse(raw) as string[]) : null;
  }

  /** Recent public posts from people the viewer is not connected to, excluding blocked/muted/hidden accounts. */
  private async buildDiscoverSnapshot(viewerId: string): Promise<string[]> {
    const rows = await this.prisma.$queryRaw<CandidateRow[]>`
      SELECT p.id, p.author_id, p.published_at AS sort_at, 'DISCOVER' AS source, p.like_count, p.dislike_count,
             p.comment_count, p.repost_count, p.repost_of_id,
             EXISTS(SELECT 1 FROM post_media pm WHERE pm.post_id = p.id) AS has_media,
             (SELECT count(*)::int FROM reports r WHERE r.post_id = p.id AND r.status = 'OPEN') AS open_reports
      FROM posts p
      JOIN user_profiles up ON up.user_id = p.author_id AND up.visibility = 'PUBLIC'
      JOIN user_settings us ON us.user_id = p.author_id AND us.discoverable
      JOIN users u ON u.id = p.author_id AND u.status = 'ACTIVE'
      WHERE p.deleted_at IS NULL AND p.status = 'PUBLISHED' AND p.audience = 'PUBLIC'
        AND p.repost_of_id IS NULL
        AND p.published_at > now() - interval '7 days'
        AND p.author_id <> ${viewerId}::uuid
        AND NOT EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${viewerId}::uuid AND f.followee_id = p.author_id)
        AND NOT EXISTS (SELECT 1 FROM user_mutes m WHERE m.muter_id = ${viewerId}::uuid AND m.muted_id = p.author_id)
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`p.author_id`, viewerId)}
      ORDER BY (p.like_count + 2 * p.comment_count + 3 * p.repost_count) DESC, p.published_at DESC
      LIMIT ${DISCOVER_POOL}`;
    return rank(await this.toCandidates(viewerId, rows), DISCOVER_WEIGHTS).map((c) => c.postId);
  }

  /** Adds per-viewer features (author affinity, hashtag interest) with two grouped queries. */
  private async toCandidates(viewerId: string, rows: CandidateRow[]): Promise<Candidate[]> {
    if (rows.length === 0) return [];
    const authorIds = [...new Set(rows.map((r) => r.author_id))];
    const postIds = rows.map((r) => r.id);
    const [affinity, interest] = await Promise.all([
      this.prisma.$queryRaw<Array<{ author_id: string; n: number }>>`
        SELECT p.author_id, count(*)::int AS n FROM (
          SELECT post_id FROM post_reactions WHERE user_id = ${viewerId}::uuid AND created_at > now() - interval '30 days'
          UNION ALL
          SELECT post_id FROM comments WHERE author_id = ${viewerId}::uuid AND created_at > now() - interval '30 days'
        ) i JOIN posts p ON p.id = i.post_id
        WHERE p.author_id = ANY(${authorIds}::uuid[])
        GROUP BY p.author_id`,
      this.prisma.$queryRaw<Array<{ post_id: string; overlap: number }>>`
        WITH mine AS (
          SELECT DISTINCT ph.hashtag_id FROM post_reactions r JOIN post_hashtags ph ON ph.post_id = r.post_id
          WHERE r.user_id = ${viewerId}::uuid AND r.type = 'LIKE' AND r.created_at > now() - interval '60 days'
        )
        SELECT ph.post_id, (count(*) FILTER (WHERE ph.hashtag_id IN (SELECT hashtag_id FROM mine)))::float / count(*) AS overlap
        FROM post_hashtags ph WHERE ph.post_id = ANY(${postIds}::uuid[])
        GROUP BY ph.post_id`,
    ]);
    const aff = new Map(affinity.map((a) => [a.author_id, a.n]));
    const int = new Map(interest.map((i) => [i.post_id, i.overlap]));
    return rows.map((r) => ({
      postId: r.id,
      authorId: r.author_id,
      publishedAt: r.sort_at,
      source: r.source,
      likes: r.like_count,
      dislikes: r.dislike_count,
      comments: r.comment_count,
      reposts: r.repost_count,
      hasMedia: r.has_media,
      authorAffinity: aff.get(r.author_id) ?? 0,
      interestOverlap: int.get(r.id) ?? 0,
      openReports: r.open_reports,
    }));
  }
}

/** If an original and reposts of it are in the same window, keep only the first (newest) occurrence. */
function dedupeReposts(rows: CandidateRow[]): CandidateRow[] {
  const seen = new Set<string>();
  return rows.filter((r) => {
    const key = r.repost_of_id ?? r.id;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
