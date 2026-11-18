import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Controller, Delete, Get, HttpCode, Module, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Transform } from 'class-transformer';
import { IsBoolean, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { Job } from 'bullmq';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { decodeCursor, encodeCursor } from '../common/pagination/cursor';
import { RelationshipService } from '../graph/relationship.service';
import { ContentModule } from '../posts/content.module';
import { PostPresenter } from '../posts/post-presenter.service';
import { PrismaService } from '../prisma/prisma.service';
import { Q } from '../queues/queues';
import { UserPresenter } from '../users/user-presenter.service';
import { MAX_SEARCH_RESULTS, PostgresSearchProvider, SearchProvider } from './search.provider';

class SearchQuery {
  @ApiPropertyOptional({ maxLength: 100 }) @IsOptional() @IsString() @MaxLength(100)
  q?: string;

  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(512)
  cursor?: string;

  @ApiPropertyOptional({ default: 20, maximum: 50 })
  @IsOptional() @Transform(({ value }) => (value === undefined ? undefined : Number(value))) @IsInt() @Min(1) @Max(50)
  limit?: number;
}

class PostSearchQuery extends SearchQuery {
  @ApiPropertyOptional({ enum: ['relevance', 'recent'] }) @IsOptional() @IsIn(['relevance', 'recent'])
  sort?: 'relevance' | 'recent';

  @ApiPropertyOptional() @IsOptional() @IsUUID()
  authorId?: string;

  @ApiPropertyOptional({ description: 'Hashtag without #' }) @IsOptional() @IsString() @MaxLength(50)
  hashtag?: string;

  @ApiPropertyOptional() @IsOptional() @Transform(({ value }) => value === 'true' || value === true) @IsBoolean()
  hasMedia?: boolean;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  since?: string;
}

const offsetOf = (cursor?: string) => (cursor ? Math.min(Number(decodeCursor<{ o: number }>(cursor, ['o']).o) || 0, MAX_SEARCH_RESULTS) : 0);
const cursorOf = (offset: number | null) => (offset === null ? null : encodeCursor({ o: offset }));
const RECENT_KEEP = 20;

@ApiTags('search')
@ApiBearerAuth()
@Controller('search')
export class SearchController {
  constructor(
    private readonly search: SearchProvider,
    private readonly users: UserPresenter,
    private readonly posts: PostPresenter,
    private readonly relationships: RelationshipService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('users')
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiOperation({ summary: 'Search people by username or name (respects blocks and discoverability)' })
  async searchUsers(@CurrentUser() a: AuthContext, @Query() q: SearchQuery) {
    const offset = offsetOf(q.cursor);
    const page = await this.search.users(a.userId, q.q ?? '', offset, q.limit ?? 20);
    const [summaries, rels] = await Promise.all([this.users.summaries(page.ids), this.relationships.many(a.userId, page.ids)]);
    if (!q.cursor && q.q?.trim()) await this.remember(a.userId, q.q);
    return {
      items: page.ids.flatMap((id) => {
        const s = summaries.get(id);
        const rel = rels.get(id);
        return s ? [{ ...s, relationship: rel ? { following: rel.following, followedBy: rel.followedBy, requested: rel.requested, isContact: rel.isContact } : null }] : [];
      }),
      nextCursor: cursorOf(page.nextOffset),
    };
  }

  @Get('posts')
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiOperation({ summary: 'Full-text post search with filters (only posts you are allowed to see)' })
  async searchPosts(@CurrentUser() a: AuthContext, @Query() q: PostSearchQuery) {
    const offset = offsetOf(q.cursor);
    const hashtag = q.hashtag ?? (q.q?.trim().startsWith('#') && !q.q.trim().includes(' ') ? q.q.trim().slice(1) : undefined);
    const text = hashtag && !q.hashtag ? '' : q.q ?? '';
    const page = await this.search.posts(a.userId, text, {
      sort: q.sort ?? 'relevance', authorId: q.authorId, hashtag, hasMedia: q.hasMedia, since: q.since ? new Date(q.since) : undefined,
    }, offset, q.limit ?? 20);
    if (!q.cursor && q.q?.trim()) await this.remember(a.userId, q.q);
    return { items: await this.posts.present(a.userId, page.ids), nextCursor: cursorOf(page.nextOffset) };
  }

  @Get('hashtags')
  async searchHashtags(@Query() q: SearchQuery) {
    return { items: await this.search.hashtags(q.q ?? '', q.limit ?? 20) };
  }

  @Get('hashtags/trending')
  @ApiOperation({ summary: 'Popular hashtags (recent public use, refreshed every 10 minutes)' })
  async trending(@Query() q: SearchQuery) {
    return { items: await this.search.trendingHashtags(q.limit ?? 20) };
  }

  @Get('suggest')
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  @ApiOperation({ summary: 'Type-ahead suggestions: people and hashtags' })
  async suggest(@CurrentUser() a: AuthContext, @Query() q: SearchQuery) {
    const term = q.q?.trim() ?? '';
    if (term.length < 1) return { users: [], hashtags: [] };
    const [users, hashtags] = await Promise.all([
      term.startsWith('#') ? Promise.resolve({ ids: [] as string[], nextOffset: null }) : this.search.users(a.userId, term, 0, 5),
      term.startsWith('@') ? Promise.resolve([]) : this.search.hashtags(term, 5),
    ]);
    const summaries = await this.users.summaries(users.ids);
    return { users: users.ids.flatMap((id) => summaries.get(id) ?? []), hashtags };
  }

  @Get('recent')
  async recent(@CurrentUser() a: AuthContext) {
    const rows = await this.prisma.recentSearch.findMany({ where: { userId: a.userId }, orderBy: { createdAt: 'desc' }, take: RECENT_KEEP });
    return { items: rows.map((r) => ({ query: r.query, searchedAt: r.createdAt.toISOString() })) };
  }

  @Delete('recent')
  @HttpCode(204)
  async clearRecent(@CurrentUser() a: AuthContext) {
    await this.prisma.recentSearch.deleteMany({ where: { userId: a.userId } });
  }

  private async remember(userId: string, raw: string) {
    const query = raw.trim().slice(0, 100);
    await this.prisma.recentSearch.upsert({ where: { userId_query: { userId, query } }, create: { userId, query }, update: { createdAt: new Date() } });
    const stale = await this.prisma.recentSearch.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, skip: RECENT_KEEP, select: { id: true } });
    if (stale.length) await this.prisma.recentSearch.deleteMany({ where: { id: { in: stale.map((s) => s.id) } } });
  }
}

/** search-index queue: derived search data (trending hashtags today; OpenSearch indexing later). */
@Processor(Q.search, { concurrency: 1 })
export class SearchIndexProcessor extends WorkerHost {
  constructor(private readonly search: PostgresSearchProvider) {
    super();
  }

  async process(job: Job): Promise<unknown> {
    if (job.name === 'trending-hashtags') return { trending: await this.search.refreshTrending() };
    throw new Error(`unknown search job ${job.name}`);
  }
}

@Module({
  imports: [ContentModule],
  controllers: [SearchController],
  providers: [PostgresSearchProvider, { provide: SearchProvider, useExisting: PostgresSearchProvider }],
  exports: [SearchProvider, PostgresSearchProvider],
})
export class SearchModule {}
