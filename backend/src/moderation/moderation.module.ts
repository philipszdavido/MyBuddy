import { InjectQueue } from '@nestjs/bullmq';
import { Body, Controller, Get, Injectable, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ModerationActionType, ReportReason, ReportStatus, ReportTargetType } from '@prisma/client';
import { Queue } from 'bullmq';
import { IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { TokenVerifier } from '../auth/token-verifier';
import { UserProvisioningService } from '../auth/user-provisioning.service';
import { CommentsService } from '../comments/comments.service';
import { AuditService } from '../common/audit.service';
import { AuthContext, CurrentUser, Roles } from '../common/decorators/auth.decorators';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, PageQuery, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { RelationshipService } from '../graph/relationship.service';
import { ContentModule } from '../posts/content.module';
import { PostsService } from '../posts/posts.service';
import { PrismaService } from '../prisma/prisma.service';
import { EmailJob, Q, RetractPostJob } from '../queues/queues';
import { RealtimePublisher } from '../realtime/realtime.publisher';

class ReportDto {
  @ApiProperty({ enum: ReportTargetType }) @IsEnum(ReportTargetType) targetType: ReportTargetType;
  @ApiProperty({ description: 'Id of the user, post, comment or message' }) @IsUUID() targetId: string;
  @ApiProperty({ enum: ReportReason }) @IsEnum(ReportReason) reason: ReportReason;
  @ApiPropertyOptional({ maxLength: 1000 }) @IsOptional() @IsString() @MaxLength(1000) details?: string;
}

class ReportsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: ReportStatus }) @IsOptional() @IsEnum(ReportStatus) status?: ReportStatus;
}

class ActionDto {
  @ApiProperty({ enum: ModerationActionType }) @IsEnum(ModerationActionType) type: ModerationActionType;
  @ApiPropertyOptional({ maxLength: 1000 }) @IsOptional() @IsString() @MaxLength(1000) note?: string;
}

/**
 * Abuse reporting and moderation. Users can report what they can see (users, posts, comments,
 * messages in their conversations); duplicates by the same reporter are folded. Moderators work a
 * queue and take actions; every action is audit-logged. Suspension locks the account immediately:
 * sessions revoked, cached identity dropped, open sockets disconnected.
 */
@Injectable()
export class ModerationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly posts: PostsService,
    private readonly comments: CommentsService,
    private readonly audit: AuditService,
    private readonly verifier: TokenVerifier,
    private readonly provisioning: UserProvisioningService,
    private readonly realtime: RealtimePublisher,
    @InjectQueue(Q.feed) private readonly feed: Queue<RetractPostJob>,
    @InjectQueue(Q.email) private readonly email: Queue<EmailJob>,
  ) {}

  async report(reporterId: string, dto: ReportDto): Promise<{ id: string }> {
    const target = await this.resolveTarget(reporterId, dto.targetType, dto.targetId);
    if (target.targetUserId === reporterId) throw AppError.badRequest('You cannot report yourself');
    const existing = await this.prisma.report.findFirst({
      where: { reporterId, targetType: dto.targetType, status: { in: ['OPEN', 'REVIEWING'] }, ...target.where },
      select: { id: true },
    });
    if (existing) return existing;
    const report = await this.prisma.report.create({
      data: { reporterId, targetType: dto.targetType, reason: dto.reason, details: dto.details, targetUserId: target.targetUserId, ...target.where },
      select: { id: true },
    });
    const reporter = await this.prisma.user.findUnique({ where: { id: reporterId }, select: { email: true } });
    if (reporter?.email) await this.email.add('report-received', { to: reporter.email, template: 'report-received' });
    return report;
  }

  async queue(status: ReportStatus = 'OPEN', cursor?: string, limit = DEFAULT_PAGE) {
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.report.findMany({
      where: { status, ...(c ? { OR: [{ createdAt: { gt: c.date } }, { createdAt: c.date, id: { gt: c.id } }] } : {}) },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], // oldest first
      take: limit + 1,
      include: {
        post: { select: { id: true, text: true, authorId: true, deletedAt: true } },
        comment: { select: { id: true, text: true, authorId: true, deletedAt: true } },
        message: { select: { id: true, text: true, senderId: true, deletedAt: true } },
        targetUser: { select: { id: true, status: true, profile: { select: { username: true, displayName: true } } } },
      },
    });
    const counts = await this.prisma.report.groupBy({ by: ['targetUserId'], where: { targetUserId: { in: rows.flatMap((r) => (r.targetUserId ? [r.targetUserId] : [])) } }, _count: true });
    const byUser = new Map(counts.map((c) => [c.targetUserId, c._count]));
    return toPage(rows, limit, (r) => ({ ...r, reportsAgainstUser: r.targetUserId ? byUser.get(r.targetUserId) ?? 0 : 0 }), (r) => timeCursor(r.createdAt, r.id));
  }

  async act(moderator: AuthContext, reportId: string, dto: ActionDto) {
    const report = await this.prisma.report.findUnique({ where: { id: reportId } });
    if (!report) throw AppError.notFound('Report');
    const { suspend, retract } = await this.prisma.$transaction(async (tx) => {
      let suspend: { userId: string; firebaseUid: string } | null = null;
      let retract: string | null = null;
      switch (dto.type) {
        case 'REMOVE_POST': {
          const post = report.postId ? await tx.post.findFirst({ where: { id: report.postId, deletedAt: null } }) : null;
          if (!post) throw AppError.badRequest('Report has no live post');
          await this.posts.softDelete(tx, post);
          retract = post.id;
          break;
        }
        case 'REMOVE_COMMENT': {
          const comment = report.commentId ? await tx.comment.findFirst({ where: { id: report.commentId, deletedAt: null } }) : null;
          if (!comment) throw AppError.badRequest('Report has no live comment');
          await this.comments.softDelete(tx, comment);
          break;
        }
        case 'REMOVE_MESSAGE': {
          if (!report.messageId) throw AppError.badRequest('Report has no message');
          await tx.message.updateMany({ where: { id: report.messageId, deletedAt: null }, data: { deletedAt: new Date(), text: null } });
          break;
        }
        case 'SUSPEND_USER': {
          if (!report.targetUserId) throw AppError.badRequest('Report has no user');
          if (report.targetUserId === moderator.userId) throw AppError.badRequest('You cannot suspend yourself');
          const user = await tx.user.update({ where: { id: report.targetUserId }, data: { status: 'SUSPENDED' }, select: { id: true, firebaseUid: true } });
          suspend = { userId: user.id, firebaseUid: user.firebaseUid };
          break;
        }
        case 'RESTORE_USER': {
          if (!report.targetUserId) throw AppError.badRequest('Report has no user');
          const user = await tx.user.update({ where: { id: report.targetUserId }, data: { status: 'ACTIVE' }, select: { firebaseUid: true } });
          await this.provisioning.invalidate(user.firebaseUid);
          break;
        }
        case 'DISMISS_REPORT':
          break;
      }
      await tx.moderationAction.create({
        data: {
          moderatorId: moderator.userId, type: dto.type, reportId, note: dto.note,
          targetUserId: report.targetUserId, postId: report.postId, commentId: report.commentId, messageId: report.messageId,
        },
      });
      await tx.report.update({ where: { id: reportId }, data: { status: dto.type === 'DISMISS_REPORT' ? 'DISMISSED' : 'ACTIONED', resolvedAt: new Date() } });
      await this.audit.record({ actorId: moderator.userId, action: `moderation.${dto.type.toLowerCase()}`, targetType: 'report', targetId: reportId, metadata: { note: dto.note ?? null } }, tx);
      return { suspend, retract };
    });

    if (retract) await this.feed.add('retract', { postId: retract }, { jobId: `rt-${retract}-${Date.now()}` });
    if (suspend) {
      await this.provisioning.invalidate(suspend.firebaseUid);
      await this.verifier.revokeSessions(suspend.firebaseUid);
      await this.realtime.toUsers([suspend.userId], 'session:revoked', { reason: 'suspended' });
    }
    return { status: 'ok' };
  }

  /** Resolves a report target the reporter is allowed to see; 404 otherwise (no probing of hidden content). */
  private async resolveTarget(reporterId: string, type: ReportTargetType, id: string) {
    switch (type) {
      case 'USER': {
        const u = await this.prisma.user.findFirst({ where: { id, status: { not: 'DELETING' } }, select: { id: true } });
        if (!u) throw AppError.notFound('User');
        return { targetUserId: u.id, where: {} };
      }
      case 'POST': {
        const p = await this.prisma.post.findFirst({ where: { id, deletedAt: null }, select: { authorId: true } });
        if (!p || !(await this.relationships.canViewPost(reporterId, id))) throw AppError.notFound('Post');
        return { targetUserId: p.authorId, where: { postId: id } };
      }
      case 'COMMENT': {
        const c = await this.prisma.comment.findFirst({ where: { id, deletedAt: null }, select: { authorId: true, postId: true } });
        if (!c || !(await this.relationships.canViewPost(reporterId, c.postId))) throw AppError.notFound('Comment');
        return { targetUserId: c.authorId, where: { commentId: id } };
      }
      case 'MESSAGE': {
        const m = await this.prisma.message.findFirst({
          where: { id, deletedAt: null, conversation: { participants: { some: { userId: reporterId, leftAt: null } } } },
          select: { senderId: true },
        });
        if (!m) throw AppError.notFound('Message');
        return { targetUserId: m.senderId, where: { messageId: id } };
      }
    }
  }
}

@ApiTags('moderation')
@ApiBearerAuth()
@Controller()
export class ModerationController {
  constructor(private readonly moderation: ModerationService) {}

  @Post('reports')
  @Throttle({ default: { limit: 20, ttl: 3_600_000 } })
  @ApiOperation({ summary: 'Report a user, post, comment or message' })
  report(@CurrentUser() a: AuthContext, @Body() dto: ReportDto) {
    return this.moderation.report(a.userId, dto);
  }

  @Get('admin/reports')
  @Roles('MODERATOR')
  queue(@Query() q: ReportsQuery) {
    return this.moderation.queue(q.status, q.cursor, q.limit);
  }

  @Post('admin/reports/:id/actions')
  @Roles('MODERATOR')
  act(@CurrentUser() a: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ActionDto) {
    return this.moderation.act(a, id, dto);
  }
}

@Module({ imports: [ContentModule], controllers: [ModerationController], providers: [ModerationService] })
export class ModerationModule {}
