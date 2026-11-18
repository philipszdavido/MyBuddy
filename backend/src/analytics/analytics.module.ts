import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Body, Controller, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsDateString, IsIn, IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
import { Job, Queue } from 'bullmq';
import { AuthContext, CurrentUser, Roles } from '../common/decorators/auth.decorators';
import { AppError } from '../common/errors/app-error';
import { PrismaService } from '../prisma/prisma.service';
import { AnalyticsEventJob, ImpressionsJob, Q } from '../queues/queues';

/** Client-reported events the API accepts. Everything else is recorded server-side. */
const CLIENT_EVENTS = ['app.open', 'video.view', 'profile.view', 'search.click'] as const;

/** Server-side metrics computed into metric_aggregates. */
export const METRICS = [
  'users.registered', 'users.active', 'posts.created', 'comments.created', 'reactions.created', 'follows.created',
  'messages.sent', 'shares', 'impressions', 'video.views', 'engagement.rate',
] as const;

class ClientEventDto {
  @ApiProperty({ enum: CLIENT_EVENTS }) @IsIn(CLIENT_EVENTS)
  type: (typeof CLIENT_EVENTS)[number];

  @ApiPropertyOptional({ description: 'Post/user/media id the event is about' }) @IsOptional() @IsUUID()
  entityId?: string;
}

class ClientEventsDto {
  @ApiProperty({ type: [ClientEventDto] }) @IsArray() @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => ClientEventDto)
  events: ClientEventDto[];
}

class MetricsQuery {
  @ApiProperty({ enum: METRICS }) @IsIn(METRICS)
  metric: string;

  @ApiPropertyOptional({ enum: ['day', 'month'] }) @IsOptional() @IsIn(['day', 'month'])
  period?: 'day' | 'month';

  @ApiPropertyOptional() @IsOptional() @IsDateString() from?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() to?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(64) dimension?: string;
}

@ApiTags('analytics')
@ApiBearerAuth()
@Controller()
export class AnalyticsController {
  constructor(private readonly prisma: PrismaService, @InjectQueue(Q.analytics) private readonly queue: Queue<AnalyticsEventJob>) {}

  @Post('analytics/events')
  @HttpCode(202)
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiOperation({ summary: 'Batch of client events (app opens, video views). Stored asynchronously; ids only, no content.' })
  async events(@CurrentUser() a: AuthContext, @Body() dto: ClientEventsDto) {
    await this.queue.addBulk(dto.events.map((e) => ({ name: 'event', data: { userId: a.userId, type: e.type, entityId: e.entityId } })));
    return { accepted: dto.events.length };
  }

  @Get('posts/:id/insights')
  @ApiOperation({ summary: 'Performance of your own post: reach, impressions, engagement, last 14 days' })
  async insights(@CurrentUser() a: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    const post = await this.prisma.post.findFirst({ where: { id, authorId: a.userId, deletedAt: null } });
    if (!post) throw AppError.notFound('Post');
    const [reach] = await this.prisma.$queryRaw<Array<{ reach: number; impressions: number }>>`
      SELECT count(DISTINCT user_id)::int AS reach, coalesce(sum(count), 0)::int AS impressions FROM post_impressions WHERE post_id = ${id}::uuid`;
    const daily = await this.prisma.$queryRaw<Array<{ day: Date; impressions: number }>>`
      SELECT day, sum(count)::int AS impressions FROM post_impressions
      WHERE post_id = ${id}::uuid AND day > current_date - 14 GROUP BY day ORDER BY day`;
    const engagements = post.likeCount + post.commentCount + post.repostCount + post.shareCount + post.saveCount;
    return {
      postId: id,
      reach: reach.reach,
      impressions: reach.impressions,
      likes: post.likeCount,
      comments: post.commentCount,
      reposts: post.repostCount,
      shares: post.shareCount,
      saves: post.saveCount,
      engagementRate: reach.reach ? engagements / reach.reach : 0,
      daily: daily.map((d) => ({ day: d.day.toISOString().slice(0, 10), impressions: d.impressions })),
    };
  }

  @Get('admin/metrics')
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Platform metrics (pre-aggregated; admin only)' })
  async metrics(@Query() q: MetricsQuery) {
    const period = q.period ?? 'day';
    const rows = await this.prisma.metricAggregate.findMany({
      where: {
        period, metric: q.metric, dimension: q.dimension ?? '',
        bucket: { gte: q.from ? new Date(q.from) : new Date(Date.now() - 30 * 86400_000), lte: q.to ? new Date(q.to) : new Date() },
      },
      orderBy: { bucket: 'asc' },
    });
    return { metric: q.metric, period, points: rows.map((r) => ({ bucket: r.bucket.toISOString().slice(0, 10), value: r.value })) };
  }
}

/**
 * analytics queue: raw events, impression de-duplication, and periodic aggregation into
 * metric_aggregates. Nothing here runs on the request path, and nothing stores message or post content.
 */
@Processor(Q.analytics, { concurrency: 3 })
export class AnalyticsProcessor extends WorkerHost {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async process(job: Job): Promise<unknown> {
    switch (job.name) {
      case 'event': {
        const e = job.data as AnalyticsEventJob;
        await this.prisma.activityEvent.create({ data: { userId: e.userId, type: e.type.slice(0, 64), entityId: e.entityId, properties: e.properties } });
        return { stored: 1 };
      }
      case 'impressions':
        return this.impressions(job.data as ImpressionsJob);
      case 'aggregate':
        return this.aggregate((job.data as { period: 'day' | 'month' }).period);
      default:
        throw new Error(`unknown analytics job ${job.name}`);
    }
  }

  /** One row per (post, viewer, day); only the first impression of the day increments the post's counter. */
  async impressions({ userId, postIds }: ImpressionsJob): Promise<{ new: number }> {
    const ids = [...new Set(postIds)];
    const inserted = await this.prisma.$queryRaw<Array<{ post_id: string; first: boolean }>>`
      INSERT INTO post_impressions (post_id, user_id, day, count)
      SELECT p.id, ${userId}::uuid, current_date, 1 FROM posts p WHERE p.id = ANY(${ids}::uuid[]) AND p.author_id <> ${userId}::uuid
      ON CONFLICT (post_id, user_id, day) DO UPDATE SET count = post_impressions.count + 1
      RETURNING post_id, (xmax = 0) AS first`;
    const first = inserted.filter((r) => r.first).map((r) => r.post_id);
    if (first.length) await this.prisma.$executeRaw`UPDATE posts SET impression_count = impression_count + 1 WHERE id = ANY(${first}::uuid[])`;
    return { new: first.length };
  }

  /** Recomputes the current and previous bucket (late events land in the right period). */
  async aggregate(period: 'day' | 'month'): Promise<{ written: number }> {
    const unit = period === 'day' ? 'day' : 'month';
    let written = 0;
    for (const back of [0, 1]) {
      written += await this.prisma.$executeRaw`
        WITH b AS (
          SELECT date_trunc(${unit}, now() - make_interval(days => ${period === 'day' ? back : 0}::int, months => ${period === 'month' ? back : 0}::int)) AS start
        ), w AS (SELECT start, start + ('1 ' || ${unit})::interval AS stop FROM b),
        m AS (
          SELECT 'users.registered' AS metric, (SELECT count(*) FROM users, w WHERE created_at >= w.start AND created_at < w.stop)::float AS value
          UNION ALL SELECT 'users.active', (SELECT count(DISTINCT user_id) FROM activity_events, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'posts.created', (SELECT count(*) FROM posts, w WHERE published_at >= w.start AND published_at < w.stop)::float
          UNION ALL SELECT 'comments.created', (SELECT count(*) FROM comments, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'reactions.created', (SELECT count(*) FROM post_reactions, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'follows.created', (SELECT count(*) FROM follows, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'messages.sent', (SELECT count(*) FROM messages, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'shares', (SELECT count(*) FROM post_shares, w WHERE created_at >= w.start AND created_at < w.stop)::float
          UNION ALL SELECT 'impressions', (SELECT coalesce(sum(count), 0) FROM post_impressions, w WHERE day >= w.start::date AND day < w.stop::date)::float
          UNION ALL SELECT 'video.views', (SELECT count(*) FROM activity_events, w WHERE type = 'video.view' AND created_at >= w.start AND created_at < w.stop)::float
        ),
        all_metrics AS (
          SELECT metric, value FROM m
          UNION ALL
          SELECT 'engagement.rate',
            CASE WHEN (SELECT value FROM m WHERE metric = 'impressions') > 0
              THEN ((SELECT value FROM m WHERE metric = 'reactions.created') + (SELECT value FROM m WHERE metric = 'comments.created') + (SELECT value FROM m WHERE metric = 'shares'))
                   / (SELECT value FROM m WHERE metric = 'impressions')
              ELSE 0 END
        )
        INSERT INTO metric_aggregates (period, bucket, metric, dimension, value, updated_at)
        SELECT ${period}, (SELECT start::date FROM b), metric, '', value, now() FROM all_metrics
        ON CONFLICT (period, bucket, metric, dimension) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`;
    }
    return { written };
  }
}

@Module({ controllers: [AnalyticsController] })
export class AnalyticsModule {}
