import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { MediaPurpose, Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { UserProvisioningService } from '../auth/user-provisioning.service';
import { TokenVerifier } from '../auth/token-verifier';
import { AuditService } from '../common/audit.service';
import { AuthContext } from '../common/decorators/auth.decorators';
import { AppError } from '../common/errors/app-error';
import { GraphService } from '../graph/graph.service';
import { RelationshipService } from '../graph/relationship.service';
import { isUniqueViolation, PrismaService, Tx } from '../prisma/prisma.service';
import { AccountDeletionJob, Q } from '../queues/queues';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { profileInclude, ProfileView, UserPresenter } from './user-presenter.service';
import { UpdateProfileDto, UpdateSettingsDto, USERNAME_PATTERN } from './users.dto';

export interface MeView extends ProfileView {
  email: string | null;
  emailVerified: boolean;
  phoneNumber: string | null;
  phoneVerified: boolean;
  role: string;
  status: string;
  settings: {
    showActivityStatus: boolean;
    sendReadReceipts: boolean;
    allowMessagesFrom: string;
    discoverable: boolean;
  };
}

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly presenter: UserPresenter,
    private readonly relationships: RelationshipService,
    private readonly graph: GraphService,
    private readonly audit: AuditService,
    private readonly verifier: TokenVerifier,
    private readonly provisioning: UserProvisioningService,
    private readonly realtime: RealtimePublisher,
    @InjectQueue(Q.accountDeletion) private readonly deletionQueue: Queue<AccountDeletionJob>,
  ) {}

  async me(userId: string): Promise<MeView> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { profile: { include: profileInclude }, settings: true },
    });
    if (!user.profile || !user.settings) throw new Error(`user ${userId} has no profile/settings`);
    const profile = await this.presenter.profile(user.profile, null);
    const s = user.settings;
    return {
      ...profile,
      email: user.email,
      emailVerified: user.emailVerified,
      phoneNumber: user.phoneNumber,
      phoneVerified: user.phoneVerified,
      role: user.role,
      status: user.status,
      settings: {
        showActivityStatus: s.showActivityStatus,
        sendReadReceipts: s.sendReadReceipts,
        allowMessagesFrom: s.allowMessagesFrom,
        discoverable: s.discoverable,
      },
    };
  }

  async updateMe(userId: string, dto: UpdateProfileDto): Promise<MeView> {
    const newFollowers = await this.prisma.$transaction(async (tx) => {
      const profile: Prisma.UserProfileUpdateInput = {};
      if (dto.username !== undefined) profile.username = dto.username;
      if (dto.displayName !== undefined) profile.displayName = dto.displayName;
      if (dto.bio !== undefined) profile.bio = dto.bio || null;
      if (dto.location !== undefined) profile.location = dto.location || null;
      if (dto.website !== undefined) profile.website = dto.website || null;
      if (dto.visibility !== undefined) profile.visibility = dto.visibility;
      if (dto.avatarMediaId !== undefined) {
        profile.avatar = dto.avatarMediaId === null
          ? { disconnect: true }
          : { connect: { id: await this.ownedReadyMedia(tx, userId, dto.avatarMediaId, MediaPurpose.AVATAR) } };
      }
      if (dto.coverMediaId !== undefined) {
        profile.cover = dto.coverMediaId === null
          ? { disconnect: true }
          : { connect: { id: await this.ownedReadyMedia(tx, userId, dto.coverMediaId, MediaPurpose.COVER) } };
      }
      if (Object.keys(profile).length) {
        try {
          await tx.userProfile.update({ where: { userId }, data: profile });
        } catch (error) {
          if (isUniqueViolation(error, 'username')) throw AppError.conflict('That username is taken', 'USERNAME_TAKEN');
          throw error;
        }
      }
      if (dto.phoneNumber !== undefined) {
        // A verified number (from the Firebase token) can't be overwritten with a self-declared one.
        await tx.user.updateMany({ where: { id: userId, phoneVerified: false }, data: { phoneNumber: dto.phoneNumber } });
      }
      // Going public: pending follow requests become follows.
      return dto.visibility === 'PUBLIC' ? this.graph.approveAllPending(tx, userId) : [];
    });
    for (const followerId of newFollowers) await this.graph.enqueueBackfill(followerId, userId);
    return this.me(userId);
  }

  async updateSettings(userId: string, dto: UpdateSettingsDto): Promise<MeView> {
    await this.prisma.userSettings.update({ where: { userId }, data: dto });
    return this.me(userId);
  }

  async usernameAvailable(username: string): Promise<{ username: string; available: boolean }> {
    if (!USERNAME_PATTERN.test(username)) return { username, available: false };
    const taken = await this.prisma.userProfile.count({ where: { username } });
    return { username, available: taken === 0 };
  }

  async byUsername(viewerId: string, username: string): Promise<ProfileView> {
    const row = await this.prisma.userProfile.findUnique({ where: { username: username.toLowerCase() }, include: profileInclude });
    if (!row) throw AppError.notFound('User');
    return this.view(viewerId, row);
  }

  async byId(viewerId: string, id: string): Promise<ProfileView> {
    const row = await this.prisma.userProfile.findUnique({ where: { userId: id }, include: profileInclude });
    if (!row) throw AppError.notFound('User');
    return this.view(viewerId, row);
  }

  private async view(viewerId: string, row: Prisma.UserProfileGetPayload<{ include: typeof profileInclude }>): Promise<ProfileView> {
    const status = await this.prisma.user.findUnique({ where: { id: row.userId }, select: { status: true } });
    if (!status || status.status !== 'ACTIVE') throw AppError.notFound('User');
    const rel = viewerId === row.userId ? null : await this.relationships.between(viewerId, row.userId);
    // Someone who blocked you does not exist from your point of view.
    if (rel?.blockedBy) throw AppError.notFound('User');
    return this.presenter.profile(row, rel);
  }

  /**
   * Account deletion (App Store requirement). The account is locked immediately (status DELETING, all
   * sessions revoked) and the data removal runs in the account-deletion queue, which is idempotent and
   * retried until it completes. The Firebase Auth user is deleted last by that job.
   */
  async requestDeletion(auth: AuthContext, requestId?: string): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: auth.userId }, data: { status: 'DELETING' } });
      await this.audit.record({ actorId: auth.userId, action: 'account.delete_requested', targetType: 'user', targetId: auth.userId, requestId }, tx);
    });
    await this.provisioning.invalidate(auth.firebaseUid);
    await this.verifier.revokeSessions(auth.firebaseUid);
    await this.realtime.toUsers([auth.userId], 'session:revoked', { reason: 'deleted' });
    await this.deletionQueue.add('delete', { userId: auth.userId, firebaseUid: auth.firebaseUid }, { jobId: `delete-${auth.userId}` });
  }

  private async ownedReadyMedia(tx: Tx, userId: string, mediaId: string, purpose: MediaPurpose): Promise<string> {
    const media = await tx.mediaAsset.findFirst({ where: { id: mediaId, ownerId: userId, purpose, deletedAt: null }, select: { id: true, status: true } });
    if (!media) throw AppError.notFound('Media');
    if (media.status !== 'READY') throw new AppError('MEDIA_NOT_READY', 'Media is still processing', 409);
    return media.id;
  }
}
