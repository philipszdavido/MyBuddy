import { Module } from '@nestjs/common';
import { CommentsService } from '../comments/comments.service';
import { ReactionsService } from '../engagement/reactions.service';
import { ContentController } from './content.controller';
import { PostPresenter } from './post-presenter.service';
import { PostsService } from './posts.service';

/** Posts, comments and reactions. */
@Module({
  controllers: [ContentController],
  providers: [PostsService, PostPresenter, CommentsService, ReactionsService],
  exports: [PostsService, PostPresenter, CommentsService],
})
export class ContentModule {}
