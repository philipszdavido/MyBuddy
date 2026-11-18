import { InjectQueue } from '@nestjs/bullmq';
import { HttpStatus, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { AuditService } from '../common/audit.service';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, Page, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { NotificationWriter } from '../notifications/notification-writer.service';
import { PrismaService, Tx } from '../prisma/prisma.service';
import { BackfillFollowJob, Q, UnfollowJob } from '../queues/queues';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';
import { normalizePhone } from '../auth/user-provisioning.service';
import { Relationship, RelationshipService } from './relationship.service';

export type FollowState = 'following' | 'requested' | 'none';

export interface UserListItem extends UserSummary {
  relationship: Omit<Relationship, 'blockedBy'>;
  /** When the edge (follow/block/mute/contact) was created */
  since: string;
}

export interface Suggestion extends UserSummary {
  reason: 'contact' | 'followed_by_people_you_follow' | 'popular';
  mutualCount: number;
}

const MAX_CONTACTS = 5000;

@Injectable()
export class GraphService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly presenter: UserPresenter,
    private readonly notifications: NotificationWriter,
    private readonly audit: AuditService,
    @InjectQueue(Q.feed) private readonly feedQueue: Queue<BackfillFollowJob | UnfollowJob>,
  ) {}

  // ─── Follow ────────────────────────────────────────────────────────────────

  async follow(viewerId: string, targetId: string): Promise<{ state: FollowState }> {
    if (viewerId === targetId) throw AppError.badRequest('You cannot follow yourself');
    const result = await this.prisma.$transaction(async (tx) => {
      const target = await this.activeTarget(tx, targetId);
      await this.assertNotBlocked(tx, viewerId, targetId);
      if (await tx.follow.findUnique({ where: { followerId_followeeId: { followerId: viewerId, followeeId: targetId } } })) {
        return { state: 'following' as const, notify: [] as string[], followed: false };
      }
      if (target.visibility === 'PRIVATE') {
        const request = await tx.followRequest.upsert({
          where: { requesterId_targetId: { requesterId: viewerId, targetId } },
          create: { requesterId: viewerId, targetId },
          update: { status: 'PENDING' },
        });
        const notify = await this.notifications.write(tx, [{
          recipientId: targetId, actorId: viewerId, type: 'FOLLOW_REQUEST', dedupeKey: `FOLLOW_REQUEST:${request.id}`,
        }]);
        return { state: 'requested' as const, notify, followed: false };
      }
      await this.createFollow(tx, viewerId, targetId);
      const notify = await this.notifications.write(tx, [{
        recipientId: targetId, actorId: viewerId, type: 'FOLLOW', dedupeKey: `FOLLOW:${viewerId}`,
      }]);
      return { state: 'following' as const, notify, followed: true };
    });
    await this.notifications.dispatch(result.notify);
    if (result.followed) await this.enqueueBackfill(viewerId, targetId);
    return { state: result.state };
  }

  async unfollow(viewerId: string, targetId: string): Promise<{ state: FollowState }> {
    const removed = await this.prisma.$transaction(async (tx) => {
      await tx.followRequest.deleteMany({ where: { requesterId: viewerId, targetId, status: 'PENDING' } });
      const did = await this.deleteFollow(tx, viewerId, targetId);
      if (did) await this.notifications.retract(tx, targetId, `FOLLOW:${viewerId}`);
      return did;
    });
    if (removed) await this.enqueueUnfollow(viewerId, targetId);
    return { state: 'none' };
  }

  /** Lets a (typically private) account remove someone from its followers. */
  async removeFollower(ownerId: string, followerId: string): Promise<void> {
    const removed = await this.prisma.$transaction((tx) => this.deleteFollow(tx, followerId, ownerId));
    if (removed) await this.enqueueUnfollow(followerId, ownerId);
  }

  async incomingRequests(ownerId: string, cursor: string | undefined, limit = DEFAULT_PAGE): Promise<Page<UserListItem & { requestId: string }>> {
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.followRequest.findMany({
      where: {
        targetId: ownerId,
        status: 'PENDING',
        ...(c ? { OR: [{ createdAt: { lt: c.date } }, { createdAt: c.date, id: { lt: c.id } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const items = await this.decorate(ownerId, rows.map((r) => ({ userId: r.requesterId, since: r.createdAt, requestId: r.id })));
    return toPage(items, limit, (i) => i, (i) => timeCursor(new Date(i.since), i.requestId));
  }

  async respondToRequest(ownerId: string, requestId: string, accept: boolean): Promise<void> {
    const result = await this.prisma.$transaction(async (tx) => {
      const request = await tx.followRequest.findFirst({ where: { id: requestId, targetId: ownerId, status: 'PENDING' } });
      if (!request) throw AppError.notFound('Follow request');
      await tx.followRequest.update({ where: { id: request.id }, data: { status: accept ? 'ACCEPTED' : 'REJECTED' } });
      await this.notifications.retract(tx, ownerId, `FOLLOW_REQUEST:${request.id}`);
      if (!accept) return { notify: [] as string[], requesterId: request.requesterId, followed: false };
      const followed = await this.createFollow(tx, request.requesterId, ownerId);
      const notify = await this.notifications.write(tx, [{
        recipientId: request.requesterId, actorId: ownerId, type: 'FOLLOW_ACCEPTED', dedupeKey: `FOLLOW_ACCEPTED:${request.id}`,
      }]);
      return { notify, requesterId: request.requesterId, followed };
    });
    await this.notifications.dispatch(result.notify);
    if (result.followed) await this.enqueueBackfill(result.requesterId, ownerId);
  }

  /** Used when an account switches from private to public: every pending request becomes a follow. */
  async approveAllPending(tx: Tx, ownerId: string): Promise<string[]> {
    const pending = await tx.followRequest.findMany({ where: { targetId: ownerId, status: 'PENDING' }, select: { id: true, requesterId: true } });
    const followed: string[] = [];
    for (const r of pending) {
      if (await this.createFollow(tx, r.requesterId, ownerId)) followed.push(r.requesterId);
    }
    if (pending.length) await tx.followRequest.updateMany({ where: { id: { in: pending.map((r) => r.id) } }, data: { status: 'ACCEPTED' } });
    return followed;
  }

  async enqueueBackfill(followerId: string, followeeId: string) {
    await this.feedQueue.add('backfill-follow', { followerId, followeeId }, { jobId: `bf-${followerId}-${followeeId}-${Date.now()}` });
  }

  private async enqueueUnfollow(followerId: string, followeeId: string) {
    await this.feedQueue.add('unfollow', { followerId, followeeId }, { jobId: `uf-${followerId}-${followeeId}-${Date.now()}` });
  }

  /** Insert + counters atomically. Returns false when the edge already existed (idempotent). */
  private async createFollow(tx: Tx, followerId: string, followeeId: string): Promise<boolean> {
    const inserted = await tx.$executeRaw`
      INSERT INTO follows (follower_id, followee_id, created_at) VALUES (${followerId}::uuid, ${followeeId}::uuid, now())
      ON CONFLICT DO NOTHING`;
    if (inserted === 0) return false;
    await tx.userProfile.update({ where: { userId: followerId }, data: { followingCount: { increment: 1 } } });
    await tx.userProfile.update({ where: { userId: followeeId }, data: { followersCount: { increment: 1 } } });
    return true;
  }

  private async deleteFollow(tx: Tx, followerId: string, followeeId: string): Promise<boolean> {
    const deleted = await tx.follow.deleteMany({ where: { followerId, followeeId } });
    if (deleted.count === 0) return false;
    await tx.$executeRaw`UPDATE user_profiles SET following_count = GREATEST(following_count - 1, 0) WHERE user_id = ${followerId}::uuid`;
    await tx.$executeRaw`UPDATE user_profiles SET followers_count = GREATEST(followers_count - 1, 0) WHERE user_id = ${followeeId}::uuid`;
    return true;
  }

  // ─── Lists ─────────────────────────────────────────────────────────────────

  async followers(viewerId: string, targetId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem>> {
    await this.assertCanSeeLists(viewerId, targetId);
    return this.edgeList(viewerId, cursor, limit, (c) => Prisma.sql`
      SELECT f.follower_id AS user_id, f.created_at AS since FROM follows f
      WHERE f.followee_id = ${targetId}::uuid ${c}
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`f.follower_id`, viewerId)}`, 'f.follower_id', 'f.created_at');
  }

  async following(viewerId: string, targetId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem>> {
    await this.assertCanSeeLists(viewerId, targetId);
    return this.edgeList(viewerId, cursor, limit, (c) => Prisma.sql`
      SELECT f.followee_id AS user_id, f.created_at AS since FROM follows f
      WHERE f.follower_id = ${targetId}::uuid ${c}
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`f.followee_id`, viewerId)}`, 'f.followee_id', 'f.created_at');
  }

  /** People who follow `targetId` and whom the viewer follows ("followed by X and 3 others"). */
  async mutualFollowers(viewerId: string, targetId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem>> {
    await this.assertCanSeeLists(viewerId, targetId);
    return this.edgeList(viewerId, cursor, limit, (c) => Prisma.sql`
      SELECT f.follower_id AS user_id, f.created_at AS since FROM follows f
      JOIN follows mine ON mine.follower_id = ${viewerId}::uuid AND mine.followee_id = f.follower_id
      WHERE f.followee_id = ${targetId}::uuid ${c}`, 'f.follower_id', 'f.created_at');
  }

  async blocked(ownerId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem>> {
    return this.edgeList(ownerId, cursor, limit, (c) => Prisma.sql`
      SELECT b.blocked_id AS user_id, b.created_at AS since FROM user_blocks b WHERE b.blocker_id = ${ownerId}::uuid ${c}`, 'b.blocked_id', 'b.created_at');
  }

  async muted(ownerId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem>> {
    return this.edgeList(ownerId, cursor, limit, (c) => Prisma.sql`
      SELECT m.muted_id AS user_id, m.created_at AS since FROM user_mutes m WHERE m.muter_id = ${ownerId}::uuid ${c}`, 'm.muted_id', 'm.created_at');
  }

  /**
   * Matched contacts. Includes each contact's phone number: the caller uploaded it from their own
   * address book, so this reveals nothing new, and the iOS app keys contacts by number.
   */
  async contacts(ownerId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserListItem & { phoneNumber: string | null }>> {
    const page = await this.edgeList(ownerId, cursor, limit, (c) => Prisma.sql`
      SELECT cl.contact_id AS user_id, cl.created_at AS since FROM contact_links cl
      JOIN users u ON u.id = cl.contact_id AND u.status = 'ACTIVE'
      WHERE cl.owner_id = ${ownerId}::uuid ${c}
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`cl.contact_id`, ownerId)}`, 'cl.contact_id', 'cl.created_at');
    const phones = new Map((await this.prisma.user.findMany({ where: { id: { in: page.items.map((i) => i.id) } }, select: { id: true, phoneNumber: true } })).map((u) => [u.id, u.phoneNumber]));
    return { items: page.items.map((i) => ({ ...i, phoneNumber: phones.get(i.id) ?? null })), nextCursor: page.nextCursor };
  }

  /**
   * Keyset-paginated (since DESC, user_id DESC) list from an edge query. `build` receives the cursor
   * predicate to splice into its WHERE clause; one extra row is fetched to know if there is a next page.
   */
  private async edgeList(
    viewerId: string,
    cursor: string | undefined,
    limit: number,
    build: (cursorPredicate: Prisma.Sql) => Prisma.Sql,
    idColumn: string,
    timeColumn: string,
  ): Promise<Page<UserListItem>> {
    const c = parseTimeCursor(cursor);
    const predicate = c
      ? Prisma.sql`AND (${Prisma.raw(timeColumn)}, ${Prisma.raw(idColumn)}) < (${c.date}, ${c.id}::uuid)`
      : Prisma.empty;
    const rows = await this.prisma.$queryRaw<Array<{ user_id: string; since: Date }>>`
      ${build(predicate)} ORDER BY since DESC, user_id DESC LIMIT ${limit + 1}`;
    const items = await this.decorate(viewerId, rows.map((r) => ({ userId: r.user_id, since: r.since })));
    return toPage(items, limit, (i) => i, (i) => timeCursor(new Date(i.since), i.id));
  }

  private async decorate<T extends { userId: string; since: Date }>(viewerId: string, rows: T[]): Promise<Array<UserListItem & Omit<T, 'userId' | 'since'>>> {
    const ids = rows.map((r) => r.userId);
    const [summaries, rels] = await Promise.all([this.presenter.summaries(ids), this.relationships.many(viewerId, ids)]);
    const out: Array<UserListItem & Omit<T, 'userId' | 'since'>> = [];
    for (const { userId, since, ...rest } of rows) {
      const summary = summaries.get(userId);
      if (!summary) continue;
      const { blockedBy: _hidden, ...relationship } = rels.get(userId) ?? emptyRelationship();
      out.push({ ...summary, relationship, since: since.toISOString(), ...(rest) });
    }
    return out;
  }

  private async assertCanSeeLists(viewerId: string, targetId: string) {
    const target = await this.prisma.userProfile.findUnique({ where: { userId: targetId }, select: { visibility: true, user: { select: { status: true } } } });
    if (!target || target.user.status !== 'ACTIVE') throw AppError.notFound('User');
    const rel = await this.relationships.between(viewerId, targetId);
    if (rel.blockedBy) throw AppError.notFound('User');
    if (!this.relationships.canSeeProfileContent(rel, target.visibility, viewerId === targetId)) {
      throw new AppError('PRIVATE_ACCOUNT', 'This account is private', HttpStatus.FORBIDDEN);
    }
  }

  // ─── Block / mute ──────────────────────────────────────────────────────────

  /**
   * Blocking severs the relationship both ways: follows and pending requests are removed (with
   * counters), feeds are cleaned asynchronously, and the blocked user can no longer see, follow,
   * message or notify the blocker.
   */
  async block(ownerId: string, targetId: string): Promise<void> {
    if (ownerId === targetId) throw AppError.badRequest('You cannot block yourself');
    await this.prisma.$transaction(async (tx) => {
      await this.activeTarget(tx, targetId);
      await tx.$executeRaw`INSERT INTO user_blocks (blocker_id, blocked_id, created_at) VALUES (${ownerId}::uuid, ${targetId}::uuid, now()) ON CONFLICT DO NOTHING`;
      await this.deleteFollow(tx, ownerId, targetId);
      await this.deleteFollow(tx, targetId, ownerId);
      await tx.followRequest.deleteMany({ where: { OR: [{ requesterId: ownerId, targetId }, { requesterId: targetId, targetId: ownerId }] } });
      await this.audit.record({ actorId: ownerId, action: 'user.block', targetType: 'user', targetId }, tx);
    });
    // Always clean feeds both ways (CONTACTS posts may be in feeds without a follow edge).
    await this.enqueueUnfollow(ownerId, targetId);
    await this.enqueueUnfollow(targetId, ownerId);
  }

  async unblock(ownerId: string, targetId: string): Promise<void> {
    await this.prisma.userBlock.deleteMany({ where: { blockerId: ownerId, blockedId: targetId } });
    await this.audit.record({ actorId: ownerId, action: 'user.unblock', targetType: 'user', targetId });
  }

  async mute(ownerId: string, targetId: string): Promise<void> {
    if (ownerId === targetId) throw AppError.badRequest('You cannot mute yourself');
    await this.activeTarget(this.prisma, targetId);
    await this.prisma.$executeRaw`INSERT INTO user_mutes (muter_id, muted_id, created_at) VALUES (${ownerId}::uuid, ${targetId}::uuid, now()) ON CONFLICT DO NOTHING`;
  }

  async unmute(ownerId: string, targetId: string): Promise<void> {
    await this.prisma.userMute.deleteMany({ where: { muterId: ownerId, mutedId: targetId } });
  }

  // ─── Contacts ──────────────────────────────────────────────────────────────

  /**
   * Replaces the caller's matched contacts with the users whose phone number appears in the uploaded
   * address book. Numbers are only used for matching and are not stored. New matches get existing
   * CONTACTS posts backfilled into their feed (pre-rebuild behaviour: contacts see each other's posts).
   */
  async syncContacts(ownerId: string, phoneNumbers: string[], mode: 'replace' | 'merge' = 'replace'): Promise<{ matched: Array<UserListItem & { phoneNumber: string | null }> }> {
    const numbers = [...new Set(phoneNumbers.map(normalizePhone).filter((n): n is string => !!n))].slice(0, MAX_CONTACTS);
    const { added } = await this.prisma.$transaction(async (tx) => {
      const matches = numbers.length
        ? await tx.user.findMany({ where: { phoneNumber: { in: numbers }, status: 'ACTIVE', id: { not: ownerId } }, select: { id: true } })
        : [];
      const matchedIds = matches.map((m) => m.id);
      if (mode === 'replace') await tx.contactLink.deleteMany({ where: { ownerId, contactId: { notIn: matchedIds } } });
      const existing = new Set((await tx.contactLink.findMany({ where: { ownerId }, select: { contactId: true } })).map((c) => c.contactId));
      const newIds = matchedIds.filter((id) => !existing.has(id));
      if (newIds.length) await tx.contactLink.createMany({ data: newIds.map((contactId) => ({ ownerId, contactId })), skipDuplicates: true });
      return { added: newIds };
    }, { timeout: 20_000 });
    // owner added X to their contacts => X now sees owner's CONTACTS posts.
    for (const contactId of added) await this.enqueueBackfill(contactId, ownerId);
    const page = await this.contacts(ownerId, undefined, 100);
    // merge = lookup: answer only for the numbers asked about.
    const asked = new Set(numbers);
    return { matched: mode === 'merge' ? page.items.filter((i) => i.phoneNumber && asked.has(i.phoneNumber)) : page.items };
  }

  // ─── Suggestions ───────────────────────────────────────────────────────────

  /**
   * "Suggested accounts": matched contacts you don't follow first, then people followed by many of
   * the accounts you follow, then popular public accounts. Excludes self, followed, requested,
   * blocked (either way), muted and non-discoverable users.
   */
  async suggestions(viewerId: string, limit = 20): Promise<Suggestion[]> {
    const rows = await this.prisma.$queryRaw<Array<{ id: string; reason: Suggestion['reason']; mutual: number }>>`
      WITH excluded AS (
        SELECT ${viewerId}::uuid AS id
        UNION SELECT followee_id FROM follows WHERE follower_id = ${viewerId}::uuid
        UNION SELECT target_id FROM follow_requests WHERE requester_id = ${viewerId}::uuid AND status = 'PENDING'
        UNION SELECT blocked_id FROM user_blocks WHERE blocker_id = ${viewerId}::uuid
        UNION SELECT blocker_id FROM user_blocks WHERE blocked_id = ${viewerId}::uuid
        UNION SELECT muted_id FROM user_mutes WHERE muter_id = ${viewerId}::uuid
      ),
      candidates AS (
        SELECT cl.contact_id AS id, 'contact' AS reason, 3 AS tier, 0 AS mutual FROM contact_links cl WHERE cl.owner_id = ${viewerId}::uuid
        UNION ALL
        SELECT f2.followee_id, 'followed_by_people_you_follow', 2, count(*)::int
        FROM follows f1 JOIN follows f2 ON f2.follower_id = f1.followee_id
        WHERE f1.follower_id = ${viewerId}::uuid
        GROUP BY f2.followee_id
        UNION ALL
        SELECT * FROM (
          SELECT up.user_id, 'popular', 1, 0 FROM user_profiles up
          WHERE up.visibility = 'PUBLIC' ORDER BY up.followers_count DESC LIMIT 200
        ) popular
      ),
      ranked AS (
        SELECT DISTINCT ON (c.id) c.id, c.reason, c.mutual, c.tier
        FROM candidates c
        JOIN users u ON u.id = c.id AND u.status = 'ACTIVE'
        JOIN user_settings s ON s.user_id = c.id AND s.discoverable
        WHERE c.id NOT IN (SELECT id FROM excluded)
        ORDER BY c.id, c.tier DESC, c.mutual DESC
      )
      SELECT id, reason, mutual FROM ranked ORDER BY tier DESC, mutual DESC, id LIMIT ${limit}`;
    const summaries = await this.presenter.summaries(rows.map((r) => r.id));
    return rows.flatMap((r) => {
      const s = summaries.get(r.id);
      return s ? [{ ...s, reason: r.reason, mutualCount: r.mutual }] : [];
    });
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  private async activeTarget(db: Tx | PrismaService, targetId: string) {
    const target = await db.userProfile.findUnique({ where: { userId: targetId }, select: { visibility: true, user: { select: { status: true } } } });
    if (!target || target.user.status !== 'ACTIVE') throw AppError.notFound('User');
    return target;
  }

  private async assertNotBlocked(tx: Tx, viewerId: string, targetId: string) {
    const rel = await this.relationships.between(viewerId, targetId, tx);
    if (rel.blockedBy) throw AppError.notFound('User');
    if (rel.blocking) throw new AppError('BLOCKED', 'Unblock this account first', HttpStatus.FORBIDDEN);
  }
}

function emptyRelationship(): Relationship {
  return { following: false, followedBy: false, requested: false, blocking: false, blockedBy: false, muting: false, isContact: false, inTheirContacts: false };
}
