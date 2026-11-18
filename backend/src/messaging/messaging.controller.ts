import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsDateString, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength,
} from 'class-validator';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { DEFAULT_PAGE, PageQuery } from '../common/pagination/cursor';
import { PresenceService } from '../realtime/presence.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { RelationshipService } from '../graph/relationship.service';
import { MAX_GROUP_SIZE, MAX_MESSAGE_LENGTH, MessagingService } from './messaging.service';

const toInt = ({ value }: { value: unknown }) => (value === undefined ? undefined : Number(value));

class CreateConversationDto {
  @ApiProperty({ type: [String], description: 'One id for a direct conversation, more for a group' })
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(MAX_GROUP_SIZE - 1) @IsUUID('4', { each: true })
  participantIds: string[];

  @ApiPropertyOptional({ maxLength: 80 }) @IsOptional() @IsString() @MaxLength(80)
  title?: string;
}

class UpdateConversationDto {
  @ApiPropertyOptional({ maxLength: 80 }) @IsOptional() @IsString() @MaxLength(80)
  title?: string;

  @ApiPropertyOptional({ nullable: true, description: 'ISO date; null unmutes' }) @IsOptional() @IsDateString()
  mutedUntil?: string | null;

  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  archived?: boolean;
}

class ConversationsQuery extends PageQuery {
  @ApiPropertyOptional({ description: 'List message requests instead of the inbox' })
  @IsOptional() @Transform(({ value }) => value === 'true' || value === true) @IsBoolean()
  requests?: boolean;
}

class MessagesQuery {
  @ApiPropertyOptional({ description: 'Older history: messages with seq < beforeSeq (newest first)' })
  @IsOptional() @Transform(toInt) @IsInt() @Min(0)
  beforeSeq?: number;

  @ApiPropertyOptional({ description: 'Catch-up after reconnect: messages with seq > afterSeq (oldest first)' })
  @IsOptional() @Transform(toInt) @IsInt() @Min(0)
  afterSeq?: number;

  @ApiPropertyOptional({ default: 50, maximum: 100 }) @IsOptional() @Transform(toInt) @IsInt() @Min(1) @Max(100)
  limit?: number;
}

class SendDto {
  @ApiProperty({ description: 'Client-generated id; resending with the same id never duplicates' })
  @IsString() @MinLength(1) @MaxLength(64)
  clientId: string;

  @ApiPropertyOptional({ maxLength: MAX_MESSAGE_LENGTH }) @IsOptional() @IsString() @MaxLength(MAX_MESSAGE_LENGTH)
  text?: string;

  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsUUID('4', { each: true })
  mediaIds?: string[];

  @ApiPropertyOptional() @IsOptional() @IsUUID()
  replyToId?: string;
}

class EditDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(MAX_MESSAGE_LENGTH)
  text: string;
}

class SeqDto {
  @ApiProperty() @IsInt() @Min(0)
  seq: number;
}

class ReactDto {
  @ApiProperty({ example: '❤️' }) @IsString() @MinLength(1) @MaxLength(16)
  emoji: string;
}

class ParticipantsDto {
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(MAX_GROUP_SIZE) @IsUUID('4', { each: true })
  userIds: string[];
}

class PresenceQuery {
  @ApiProperty({ type: String, description: 'Comma-separated user ids (max 100)' })
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? value.split(',').filter(Boolean) : value))
  @IsArray() @ArrayMaxSize(100) @IsUUID('4', { each: true })
  ids: string[];
}

const uuid = new ParseUUIDPipe();

@ApiTags('messaging')
@ApiBearerAuth()
@Controller()
export class MessagingController {
  constructor(
    private readonly messaging: MessagingService,
    private readonly presence: PresenceService,
    private readonly relationships: RelationshipService,
  ) {}

  @Get('conversations')
  list(@CurrentUser() a: AuthContext, @Query() q: ConversationsQuery) {
    return this.messaging.listConversations(a.userId, q.cursor, q.limit ?? DEFAULT_PAGE, q.requests ?? false);
  }

  @Post('conversations')
  @ApiOperation({ summary: 'Start (or reopen) a direct conversation, or create a group' })
  create(@CurrentUser() a: AuthContext, @Body() dto: CreateConversationDto) {
    return this.messaging.createConversation(a.userId, dto.participantIds, dto.title);
  }

  @Get('conversations/unread-count')
  async unread(@CurrentUser() a: AuthContext) {
    return { unread: await this.messaging.unreadTotal(a.userId) };
  }

  @Get('conversations/:id')
  get(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.messaging.conversation(a.userId, id);
  }

  @Patch('conversations/:id')
  update(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: UpdateConversationDto) {
    return this.messaging.updateConversation(a.userId, id, dto);
  }

  @Post('conversations/:id/accept')
  @ApiOperation({ summary: 'Accept a message request' })
  accept(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.messaging.acceptRequest(a.userId, id);
  }

  @Delete('conversations/:id')
  @HttpCode(204)
  @ApiOperation({ summary: 'Leave a group, or delete a direct conversation for yourself' })
  async leave(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    await this.messaging.leave(a.userId, id);
  }

  @Post('conversations/:id/participants')
  add(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ParticipantsDto) {
    return this.messaging.addParticipants(a.userId, id, dto.userIds);
  }

  @Delete('conversations/:id/participants/:userId')
  @HttpCode(204)
  async removeParticipant(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Param('userId', uuid) userId: string) {
    await this.messaging.removeParticipant(a.userId, id, userId);
  }

  @Get('conversations/:id/messages')
  messages(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Query() q: MessagesQuery) {
    return this.messaging.messages(a.userId, id, { beforeSeq: q.beforeSeq, afterSeq: q.afterSeq, limit: q.limit ?? 50 });
  }

  @Post('conversations/:id/messages')
  @ApiOperation({ summary: 'Send a message (REST fallback for the socket `message:send` event)' })
  send(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: SendDto) {
    return this.messaging.send(a.userId, id, dto);
  }

  @Post('conversations/:id/read')
  read(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: SeqDto) {
    return this.messaging.markRead(a.userId, id, dto.seq);
  }

  @Post('conversations/:id/delivered')
  delivered(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: SeqDto) {
    return this.messaging.markDelivered(a.userId, id, dto.seq);
  }

  @Patch('messages/:id')
  edit(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: EditDto) {
    return this.messaging.edit(a.userId, id, dto.text);
  }

  @Delete('messages/:id')
  @HttpCode(204)
  async deleteMessage(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    await this.messaging.remove(a.userId, id);
  }

  @Post('messages/:id/reactions')
  react(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ReactDto) {
    return this.messaging.react(a.userId, id, dto.emoji, true);
  }

  @Delete('messages/:id/reactions/:emoji')
  unreact(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Param('emoji') emoji: string) {
    return this.messaging.react(a.userId, id, emoji, false);
  }

  @Get('presence')
  @ApiOperation({ summary: 'Online status and last seen (respects each user’s activity-status setting)' })
  async presenceOf(@CurrentUser() a: AuthContext, @Query() q: PresenceQuery) {
    const rels = await this.relationships.many(a.userId, q.ids);
    return this.presence.views(q.ids.filter((id) => id !== a.userId && !rels.get(id)?.blocking && !rels.get(id)?.blockedBy));
  }
}

@Module({
  controllers: [MessagingController],
  providers: [MessagingService, PresenceService, RealtimeGateway],
  exports: [MessagingService],
})
export class MessagingModule {}
