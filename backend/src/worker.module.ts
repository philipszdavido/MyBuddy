import { Module } from '@nestjs/common';
import { AccountDeletionProcessor } from './accounts/account-deletion.processor';
import { AnalyticsProcessor } from './analytics/analytics.module';
import { coreImports } from './app.module';
import { AuthModule } from './auth/auth.module';
import { CleanupProcessor, Schedules } from './cleanup/cleanup.processor';
import { EmailProcessor } from './email/email.processor';
import { FeedProcessor } from './feed/feed.processor';
import { ImageProcessor, VideoProcessor } from './media/media.processors';
import { FcmSender, FirebaseFcmSender } from './notifications/fcm.sender';
import { NotificationProcessor } from './notifications/notification.processor';
import { NotificationsService } from './notifications/notifications.service';
import { SearchIndexProcessor } from './search/search.module';
import { PostgresSearchProvider } from './search/search.provider';

/** Every BullMQ processor, one per queue. Imported by the worker process and by integration tests. */
@Module({
  providers: [
    FeedProcessor,
    ImageProcessor,
    VideoProcessor,
    NotificationProcessor,
    NotificationsService,
    { provide: FcmSender, useClass: FirebaseFcmSender },
    AccountDeletionProcessor,
    EmailProcessor,
    CleanupProcessor,
    AnalyticsProcessor,
    SearchIndexProcessor,
    PostgresSearchProvider,
  ],
})
export class ProcessorsModule {}

/** Worker process root: shared infrastructure + processors + recurring job schedules. */
@Module({ imports: [...coreImports, AuthModule, ProcessorsModule], providers: [Schedules] })
export class WorkerModule {}
