import { InjectQueue } from '@nestjs/bullmq';
import { Body, Controller, Get, HttpCode, Module, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Queue } from 'bullmq';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsUUID } from 'class-validator';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { DEFAULT_PAGE, PageQuery } from '../common/pagination/cursor';
import { ContentModule } from '../posts/content.module';
import { ImpressionsJob, Q } from '../queues/queues';
import { FeedService } from './feed.service';

class ImpressionsDto {
  @ApiProperty({ type: [String], maxItems: 50 })
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(50) @IsUUID('4', { each: true })
  postIds: string[];
}

@ApiTags('feed')
@ApiBearerAuth()
@Controller('feed')
export class FeedController {
  constructor(
    private readonly feed: FeedService,
    @InjectQueue(Q.analytics) private readonly analytics: Queue<ImpressionsJob>,
  ) {}

  @Get('following')
  @ApiOperation({ summary: 'Home feed: contacts and followed accounts, ranked within each page window' })
  following(@CurrentUser() a: AuthContext, @Query() q: PageQuery) {
    return this.feed.following(a.userId, q.cursor, q.limit ?? DEFAULT_PAGE);
  }

  @Get('discover')
  @ApiOperation({ summary: 'Recommended public posts from accounts you do not follow' })
  discover(@CurrentUser() a: AuthContext, @Query() q: PageQuery) {
    return this.feed.discover(a.userId, q.cursor, q.limit ?? DEFAULT_PAGE);
  }

  @Post('impressions')
  @HttpCode(202)
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  @ApiOperation({ summary: 'Report posts that were on screen (batched by the client). Processed asynchronously.' })
  async impressions(@CurrentUser() a: AuthContext, @Body() dto: ImpressionsDto) {
    await this.analytics.add('impressions', { userId: a.userId, postIds: dto.postIds });
    return { accepted: dto.postIds.length };
  }
}

@Module({ imports: [ContentModule], controllers: [FeedController], providers: [FeedService], exports: [FeedService] })
export class FeedModule {}
