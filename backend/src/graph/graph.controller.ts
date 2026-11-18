import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { PageQuery } from '../common/pagination/cursor';
import { GraphService } from './graph.service';

class SyncContactsDto {
  @ApiProperty({ type: [String], description: 'Phone numbers from the device address book (any format). Max 5000.', maxItems: 5000 })
  @IsArray() @ArrayMaxSize(5000) @IsString({ each: true }) @MaxLength(32, { each: true })
  phoneNumbers: string[];

  @ApiPropertyOptional({ enum: ['replace', 'merge'], default: 'replace', description: 'replace = this is the whole address book; merge = only add matches (lookups)' })
  @IsOptional() @IsIn(['replace', 'merge'])
  mode?: 'replace' | 'merge';
}

class RespondDto {
  @ApiProperty() @IsBoolean()
  accept: boolean;
}

const id = new ParseUUIDPipe();

@ApiTags('social-graph')
@ApiBearerAuth()
@Controller()
export class GraphController {
  constructor(private readonly graph: GraphService) {}

  @Post('users/:id/follow')
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiOperation({ summary: 'Follow (public account) or send a follow request (private account). Idempotent.' })
  follow(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    return this.graph.follow(auth.userId, target);
  }

  @Delete('users/:id/follow')
  @ApiOperation({ summary: 'Unfollow, or cancel a pending follow request. Idempotent.' })
  unfollow(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    return this.graph.unfollow(auth.userId, target);
  }

  @Get('users/:id/followers')
  followers(@CurrentUser() auth: AuthContext, @Param('id', id) target: string, @Query() q: PageQuery) {
    return this.graph.followers(auth.userId, target, q.cursor, q.limit);
  }

  @Get('users/:id/following')
  following(@CurrentUser() auth: AuthContext, @Param('id', id) target: string, @Query() q: PageQuery) {
    return this.graph.following(auth.userId, target, q.cursor, q.limit);
  }

  @Get('users/:id/mutual-followers')
  mutual(@CurrentUser() auth: AuthContext, @Param('id', id) target: string, @Query() q: PageQuery) {
    return this.graph.mutualFollowers(auth.userId, target, q.cursor, q.limit);
  }

  @Delete('users/me/followers/:id')
  @HttpCode(204)
  async removeFollower(@CurrentUser() auth: AuthContext, @Param('id', id) follower: string) {
    await this.graph.removeFollower(auth.userId, follower);
  }

  @Get('follow-requests')
  requests(@CurrentUser() auth: AuthContext, @Query() q: PageQuery) {
    return this.graph.incomingRequests(auth.userId, q.cursor, q.limit);
  }

  @Post('follow-requests/:id/respond')
  @HttpCode(204)
  async respond(@CurrentUser() auth: AuthContext, @Param('id', id) requestId: string, @Body() dto: RespondDto) {
    await this.graph.respondToRequest(auth.userId, requestId, dto.accept);
  }

  @Post('users/:id/block')
  @HttpCode(204)
  async block(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    await this.graph.block(auth.userId, target);
  }

  @Delete('users/:id/block')
  @HttpCode(204)
  async unblock(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    await this.graph.unblock(auth.userId, target);
  }

  @Get('users/me/blocked')
  blocked(@CurrentUser() auth: AuthContext, @Query() q: PageQuery) {
    return this.graph.blocked(auth.userId, q.cursor, q.limit);
  }

  @Post('users/:id/mute')
  @HttpCode(204)
  async mute(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    await this.graph.mute(auth.userId, target);
  }

  @Delete('users/:id/mute')
  @HttpCode(204)
  async unmute(@CurrentUser() auth: AuthContext, @Param('id', id) target: string) {
    await this.graph.unmute(auth.userId, target);
  }

  @Get('users/me/muted')
  muted(@CurrentUser() auth: AuthContext, @Query() q: PageQuery) {
    return this.graph.muted(auth.userId, q.cursor, q.limit);
  }

  @Post('contacts/sync')
  @Throttle({ default: { limit: 10, ttl: 3_600_000 } })
  @ApiOperation({ summary: 'Match the device address book against MyBuddy users and replace the contact list.' })
  sync(@CurrentUser() auth: AuthContext, @Body() dto: SyncContactsDto) {
    return this.graph.syncContacts(auth.userId, dto.phoneNumbers, dto.mode ?? 'replace');
  }

  @Get('contacts')
  contacts(@CurrentUser() auth: AuthContext, @Query() q: PageQuery) {
    return this.graph.contacts(auth.userId, q.cursor, q.limit);
  }

  @Get('users/me/suggestions')
  suggestions(@CurrentUser() auth: AuthContext) {
    return this.graph.suggestions(auth.userId);
  }
}

@Module({ controllers: [GraphController], providers: [GraphService], exports: [GraphService] })
export class GraphModule {}
