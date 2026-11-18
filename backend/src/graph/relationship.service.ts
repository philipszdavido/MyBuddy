import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService, Tx } from '../prisma/prisma.service';

export interface Relationship {
  /** viewer follows target */
  following: boolean;
  /** target follows viewer */
  followedBy: boolean;
  /** viewer has a pending follow request to target */
  requested: boolean;
  /** viewer blocked target */
  blocking: boolean;
  /** target blocked viewer (exposed only as "unavailable", never as a flag) */
  blockedBy: boolean;
  muting: boolean;
  /** target is in the viewer's matched contacts */
  isContact: boolean;
  /** viewer is in the target's matched contacts (can see the target's CONTACTS posts) */
  inTheirContacts: boolean;
}

/**
 * Single place that answers "what is A to B". Every privacy decision (profile view, post visibility,
 * messaging, notifications, feed) goes through here or through `visiblePostFilter`, so block, mute and
 * private-account rules cannot drift between modules.
 */
@Injectable()
export class RelationshipService {
  constructor(private readonly prisma: PrismaService) {}

  async between(viewerId: string, targetId: string, tx?: Tx): Promise<Relationship> {
    if (viewerId === targetId) {
      return { following: false, followedBy: false, requested: false, blocking: false, blockedBy: false, muting: false, isContact: false, inTheirContacts: false };
    }
    const db = tx ?? this.prisma;
    const [row] = await db.$queryRaw<Array<Record<keyof Relationship, boolean>>>`
      SELECT
        EXISTS(SELECT 1 FROM follows WHERE follower_id = ${viewerId}::uuid AND followee_id = ${targetId}::uuid) AS "following",
        EXISTS(SELECT 1 FROM follows WHERE follower_id = ${targetId}::uuid AND followee_id = ${viewerId}::uuid) AS "followedBy",
        EXISTS(SELECT 1 FROM follow_requests WHERE requester_id = ${viewerId}::uuid AND target_id = ${targetId}::uuid AND status = 'PENDING') AS "requested",
        EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = ${viewerId}::uuid AND blocked_id = ${targetId}::uuid) AS "blocking",
        EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = ${targetId}::uuid AND blocked_id = ${viewerId}::uuid) AS "blockedBy",
        EXISTS(SELECT 1 FROM user_mutes WHERE muter_id = ${viewerId}::uuid AND muted_id = ${targetId}::uuid) AS "muting",
        EXISTS(SELECT 1 FROM contact_links WHERE owner_id = ${viewerId}::uuid AND contact_id = ${targetId}::uuid) AS "isContact",
        EXISTS(SELECT 1 FROM contact_links WHERE owner_id = ${targetId}::uuid AND contact_id = ${viewerId}::uuid) AS "inTheirContacts"`;
    return row;
  }

  /** Batch form for lists (followers, search results): one query, no N+1. */
  async many(viewerId: string, targetIds: string[]): Promise<Map<string, Relationship>> {
    const ids = [...new Set(targetIds)].filter((id) => id !== viewerId);
    const result = new Map<string, Relationship>();
    if (ids.length === 0) return result;
    const rows = await this.prisma.$queryRaw<Array<{ id: string } & Record<keyof Relationship, boolean>>>`
      SELECT t.id,
        EXISTS(SELECT 1 FROM follows WHERE follower_id = ${viewerId}::uuid AND followee_id = t.id) AS "following",
        EXISTS(SELECT 1 FROM follows WHERE follower_id = t.id AND followee_id = ${viewerId}::uuid) AS "followedBy",
        EXISTS(SELECT 1 FROM follow_requests WHERE requester_id = ${viewerId}::uuid AND target_id = t.id AND status = 'PENDING') AS "requested",
        EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = ${viewerId}::uuid AND blocked_id = t.id) AS "blocking",
        EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = t.id AND blocked_id = ${viewerId}::uuid) AS "blockedBy",
        EXISTS(SELECT 1 FROM user_mutes WHERE muter_id = ${viewerId}::uuid AND muted_id = t.id) AS "muting",
        EXISTS(SELECT 1 FROM contact_links WHERE owner_id = ${viewerId}::uuid AND contact_id = t.id) AS "isContact",
        EXISTS(SELECT 1 FROM contact_links WHERE owner_id = t.id AND contact_id = ${viewerId}::uuid) AS "inTheirContacts"
      FROM unnest(${ids}::uuid[]) AS t(id)`;
    for (const { id, ...rel } of rows) result.set(id, rel);
    return result;
  }

  async isBlockedEitherWay(a: string, b: string, tx?: Tx): Promise<boolean> {
    if (a === b) return false;
    const db = tx ?? this.prisma;
    const count = await db.userBlock.count({
      where: { OR: [{ blockerId: a, blockedId: b }, { blockerId: b, blockedId: a }] },
    });
    return count > 0;
  }

  /** Users who blocked `userId` or whom `userId` blocked: excluded from feeds, search, suggestions. */
  blockedEitherWaySql(userIdColumn: Prisma.Sql, viewer: string | Prisma.Sql): Prisma.Sql {
    const v = viewerSql(viewer);
    return Prisma.sql`NOT EXISTS (
      SELECT 1 FROM user_blocks b
      WHERE (b.blocker_id = ${v} AND b.blocked_id = ${userIdColumn})
         OR (b.blocker_id = ${userIdColumn} AND b.blocked_id = ${v}))`;
  }

  /**
   * SQL predicate: may `viewerId` see post `p` (alias), given its audience and author privacy?
   * Author always sees own posts. Blocks hide in both directions. Private authors' non-CONTACTS posts
   * require an accepted follow. `viewer` is a user id, or a SQL column for set-based checks
   * (e.g. pruning feed_entries for every recipient at once).
   */
  visiblePostSql(viewer: string | Prisma.Sql, alias = 'p'): Prisma.Sql {
    const p = Prisma.raw(alias);
    const v = viewerSql(viewer);
    return Prisma.sql`(
      ${p}.deleted_at IS NULL AND ${p}.status = 'PUBLISHED'
      AND (
        ${p}.author_id = ${v}
        OR (
          ${this.blockedEitherWaySql(Prisma.sql`${p}.author_id`, viewer)}
          AND (
            (${p}.audience = 'CONTACTS' AND EXISTS (
              SELECT 1 FROM contact_links c WHERE c.owner_id = ${p}.author_id AND c.contact_id = ${v}))
            OR (${p}.audience = 'FOLLOWERS' AND EXISTS (
              SELECT 1 FROM follows f WHERE f.follower_id = ${v} AND f.followee_id = ${p}.author_id))
            OR (${p}.audience = 'PUBLIC' AND (
              EXISTS (SELECT 1 FROM user_profiles up WHERE up.user_id = ${p}.author_id AND up.visibility = 'PUBLIC')
              OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${v} AND f.followee_id = ${p}.author_id)))
          )
        )
      )
    )`;
  }

  async canViewPost(viewerId: string, postId: string, tx?: Tx): Promise<boolean> {
    const db = tx ?? this.prisma;
    const rows = await db.$queryRaw<Array<{ ok: boolean }>>`
      SELECT ${this.visiblePostSql(viewerId)} AS ok FROM posts p WHERE p.id = ${postId}::uuid`;
    return rows[0]?.ok === true;
  }

  /** May viewer see the target's follower/following lists and profile posts tab? */
  canSeeProfileContent(rel: Relationship, targetVisibility: 'PUBLIC' | 'PRIVATE', isSelf: boolean): boolean {
    if (isSelf) return true;
    if (rel.blockedBy || rel.blocking) return false;
    return targetVisibility === 'PUBLIC' || rel.following;
  }
}

/** A user id parameter, or an already-built SQL expression (column reference). */
function viewerSql(viewer: string | Prisma.Sql): Prisma.Sql {
  return typeof viewer === 'string' ? Prisma.sql`${viewer}::uuid` : viewer;
}
