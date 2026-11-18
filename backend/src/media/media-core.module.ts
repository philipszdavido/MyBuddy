import { Global, Module } from '@nestjs/common';
import { MediaCleanup } from './media-cleanup';
import { MediaPresenter } from './media-presenter.service';
import { StorageService } from './storage.service';

/** R2 access and URL presentation, shared by API and workers. */
@Global()
@Module({ providers: [StorageService, MediaPresenter, MediaCleanup], exports: [StorageService, MediaPresenter, MediaCleanup] })
export class MediaCoreModule {}
