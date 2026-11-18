import { Global, Module } from '@nestjs/common';
import { UserPresenter } from './user-presenter.service';

/** User summaries/profile presentation, shared by every module that embeds authors. */
@Global()
@Module({ providers: [UserPresenter], exports: [UserPresenter] })
export class UsersCoreModule {}
