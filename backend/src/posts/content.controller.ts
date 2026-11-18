import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ReactionType } from '@prisma/client';
import { IsEnum, IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { MAX_COMMENT_LENGTH, CommentsService } from '../comments/comments.service';
import { AuthContext, CurrentUser } from '../common/decorators/auth.decorators';
import { PageQuery } from '../common/pagination/cursor';
import { ReactionsService } from '../engagement/reactions.service';
import { CreatePostDto, ShareDto, UpdatePostDto } from './posts.dto';
import { PostsService } from './posts.service';

class ReactionDto {
  @ApiProperty({ enum: ReactionType }) @IsEnum(ReactionType)
  type: ReactionType;
}

class ReactorsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: ReactionType }) @IsOptional() @IsEnum(ReactionType)
  type?: ReactionType;
}

class CommentDto {
  @ApiProperty({ maxLength: MAX_COMMENT_LENGTH }) @IsString() @MinLength(1) @MaxLength(MAX_COMMENT_LENGTH)
  text: string;

  @ApiPropertyOptional({ description: 'Client-generated id for idempotent retries' })
  @IsOptional() @IsString() @MaxLength(64)
  clientId?: string;
}

class ReplyDto extends CommentDto {}

class CreateCommentDto extends CommentDto {
  @ApiPropertyOptional({ description: 'Reply to this comment' }) @IsOptional() @IsUUID()
  parentId?: string;
}

const uuid = new ParseUUIDPipe();
const WRITE_LIMIT = { default: { limit: 30, ttl: 60_000 } };

@ApiTags('posts')
@ApiBearerAuth()
@Controller()
export class ContentController {
  constructor(
    private readonly posts: PostsService,
    private readonly reactions: ReactionsService,
    private readonly comments: CommentsService,
  ) {}

  // Posts
  @Post('posts')
  @Throttle(WRITE_LIMIT)
  @ApiOperation({ summary: 'Create a post (text, images, video, gallery, quote) or a draft' })
  create(@CurrentUser() a: AuthContext, @Body() dto: CreatePostDto) {
    return this.posts.create(a.userId, dto);
  }

  @Get('posts/drafts')
  drafts(@CurrentUser() a: AuthContext, @Query() q: PageQuery) {
    return this.posts.drafts(a.userId, q.cursor, q.limit);
  }

  @Get('posts/saved')
  saved(@CurrentUser() a: AuthContext, @Query() q: PageQuery) {
    return this.posts.savedPosts(a.userId, q.cursor, q.limit);
  }

  @Get('posts/:id')
  get(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.get(a.userId, id);
  }

  @Patch('posts/:id')
  update(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: UpdatePostDto) {
    return this.posts.update(a.userId, id, dto);
  }

  @Post('posts/:id/publish')
  publish(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.publishDraft(a.userId, id);
  }

  @Delete('posts/:id')
  @HttpCode(204)
  async remove(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    await this.posts.remove(a, id);
  }

  @Get('users/:id/posts')
  byAuthor(@CurrentUser() a: AuthContext, @Param('id', uuid) userId: string, @Query() q: PageQuery) {
    return this.posts.byAuthor(a.userId, userId, q.cursor, q.limit);
  }

  @Post('posts/:id/pin')
  pin(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.pin(a.userId, id, true);
  }

  @Delete('posts/:id/pin')
  unpin(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.pin(a.userId, id, false);
  }

  @Post('posts/:id/repost')
  @Throttle(WRITE_LIMIT)
  repost(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.repost(a.userId, id);
  }

  @Delete('posts/:id/repost')
  @HttpCode(204)
  async undoRepost(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    await this.posts.undoRepost(a.userId, id);
  }

  @Post('posts/:id/share')
  @Throttle(WRITE_LIMIT)
  share(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ShareDto) {
    return this.posts.share(a.userId, id, dto.channel);
  }

  @Post('posts/:id/save')
  save(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.save(a.userId, id, true);
  }

  @Delete('posts/:id/save')
  unsave(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.posts.save(a.userId, id, false);
  }

  // Reactions on posts
  @Post('posts/:id/like')
  like(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('post', id, a.userId, 'LIKE');
  }

  @Delete('posts/:id/like')
  unlike(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('post', id, a.userId, null);
  }

  @Post('posts/:id/reactions')
  react(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ReactionDto) {
    return this.reactions.set('post', id, a.userId, dto.type);
  }

  @Delete('posts/:id/reactions')
  unreact(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('post', id, a.userId, null);
  }

  @Get('posts/:id/reactions')
  reactors(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Query() q: ReactorsQuery) {
    return this.reactions.reactors('post', id, a.userId, q.type, q.cursor, q.limit);
  }

  // Comments
  @Get('posts/:id/comments')
  listComments(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Query() q: PageQuery) {
    return this.comments.list(a.userId, id, q.cursor, q.limit);
  }

  @Post('posts/:id/comments')
  @Throttle(WRITE_LIMIT)
  comment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: CreateCommentDto) {
    return this.comments.create(a.userId, id, dto.text, dto.parentId, dto.clientId);
  }

  @Patch('comments/:id')
  editComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: CommentDto) {
    return this.comments.update(a.userId, id, dto.text);
  }

  @Delete('comments/:id')
  @HttpCode(204)
  async deleteComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    await this.comments.remove(a, id);
  }

  @Get('comments/:id/replies')
  replies(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Query() q: PageQuery) {
    return this.comments.replies(a.userId, id, q.cursor, q.limit);
  }

  @Post('comments/:id/replies')
  @Throttle(WRITE_LIMIT)
  async reply(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ReplyDto) {
    const parent = await this.comments.postOf(id);
    return this.comments.create(a.userId, parent, dto.text, id, dto.clientId);
  }

  @Post('comments/:id/like')
  likeComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('comment', id, a.userId, 'LIKE');
  }

  @Delete('comments/:id/like')
  unlikeComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('comment', id, a.userId, null);
  }

  @Post('comments/:id/reactions')
  reactComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string, @Body() dto: ReactionDto) {
    return this.reactions.set('comment', id, a.userId, dto.type);
  }

  @Delete('comments/:id/reactions')
  unreactComment(@CurrentUser() a: AuthContext, @Param('id', uuid) id: string) {
    return this.reactions.set('comment', id, a.userId, null);
  }
}
