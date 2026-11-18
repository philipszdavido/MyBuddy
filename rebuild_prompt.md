# MyBuddy — Complete Social Media Backend Rebuild

You are a senior software architect, principal backend engineer, database architect, and full-stack developer.

Your task is to **rebuild and modernize the existing MyBuddy social media platform** using a production-ready, scalable backend architecture.

This is an existing project, not a new application. You must inspect the repository, understand its current implementation, and rebuild the social media functionality without unnecessarily changing the existing frontend, design system, branding, or unrelated features.

The objective is to turn MyBuddy into a robust social media platform with an architecture capable of supporting substantial user growth.

---

# 1. Technology Stack

Implement the following architecture.

| Component | Technology |
|---|---|
| Frontend | Preserve existing frontend framework |
| Backend API | NestJS + TypeScript |
| API architecture | REST API |
| Authentication | Firebase Authentication |
| Primary database | PostgreSQL |
| ORM | Use the existing ORM if suitable; otherwise Prisma |
| Caching | Redis |
| Real-time communication | Socket.IO / WebSockets |
| Push notifications | Firebase Cloud Messaging |
| Image and video storage | Cloudflare R2 |
| Background processing | BullMQ |
| Search | PostgreSQL initially |
| Advanced search (future) | OpenSearch |
| Analytics | PostgreSQL + analytics pipeline |
| Deployment | Docker-compatible architecture |

Use a **modular monolith architecture** with independently organized backend modules and background workers.

Do not introduce microservices prematurely.

# 2. First: Audit the Existing Project

Before writing or modifying code:

1. Inspect the complete repository structure.
2. Identify the existing frontend framework and version.
3. Identify the current backend architecture.
4. Inspect the existing Firebase integration.
5. Identify all existing social media features.
6. Inspect existing database models, API endpoints, authentication flows and services.
7. Identify existing user data and storage dependencies.
8. Identify reusable components and existing UI functionality.
9. Identify incomplete, broken or duplicated implementations.
10. Document the migration plan.

Create an architecture document describing:
- Existing architecture.
- Proposed architecture.
- Database migration strategy.
- Firebase integration strategy.
- API structure.
- Real-time communication architecture.
- Media storage migration.
- Background processing architecture.

**Important:** Do not immediately delete existing code or replace the frontend. Understand the application before making architectural decisions.

# 3. Authentication — Firebase Authentication

Keep Firebase Authentication as MyBuddy's identity provider.

Support:
- Email and password authentication.
- Google authentication.
- Apple authentication if already supported.
- Password reset.
- Email verification.
- Account reauthentication where required.
- Session management.
- Account deletion.

Backend requirements:

- Use Firebase Admin SDK.
- Verify Firebase ID tokens on the NestJS backend.
- Implement a reusable authentication guard.
- Implement role-based and permission-based authorization.
- Extract the authenticated Firebase UID.
- Associate Firebase UIDs with PostgreSQL user records.
- Automatically synchronize new authenticated users with PostgreSQL.
- Never trust user IDs supplied by the frontend.
- Never expose Firebase Admin credentials to the frontend.

Create a secure user provisioning and synchronization mechanism.

PostgreSQL must become the primary source of truth for MyBuddy user profiles and social relationships.

# 4. PostgreSQL Database Architecture

Design a normalized, indexed and scalable relational database.

Create appropriate entities and relationships for:

### User management
- Users
- UserProfiles
- UserSettings
- UserSessions (if needed)
- UserDevices
- UserRoles
- UserBlocks
- UserReports

### Social networking
- Follows
- FollowRequests (if private accounts are supported)
- Friendships (only if the existing product supports friendships)
- UserConnections
- CloseFriends (if supported)

### Content
- Posts
- PostMedia
- Comments
- CommentReplies
- PostLikes
- CommentLikes
- Reactions
- Hashtags
- PostHashtags
- Mentions
- SavedPosts
- Reposts
- PostShares

### Messaging
- Conversations
- ConversationParticipants
- Messages
- MessageAttachments
- MessageReactions
- MessageReadReceipts
- MessageDeliveryReceipts

### Notifications
- Notifications
- NotificationPreferences
- NotificationDeliveries
- DeviceTokens

### Stories (if supported by the existing MyBuddy product)
- Stories
- StoryMedia
- StoryViews
- StoryReactions

### Moderation
- Reports
- ModerationActions
- BlockedUsers
- MutedUsers

### Analytics
- UserActivityEvents
- PostImpressions
- EngagementEvents

Use UUID primary keys where appropriate.

Requirements:
- Foreign key constraints.
- Appropriate unique constraints.
- Database indexes.
- Composite indexes for frequently queried relationships.
- Created and updated timestamps.
- Soft deletion where appropriate.
- Transactional operations for critical actions.
- Pagination support.
- Database migrations.

Avoid storing large media files directly in PostgreSQL.

Use appropriate PostgreSQL JSONB columns only for flexible metadata, not as a replacement for properly modeled relational data.

# 5. User Profiles

Rebuild the profile functionality.

Each profile should support:

- Username.
- Display name.
- Profile picture.
- Cover image.
- Bio.
- Location (optional).
- Website (optional).
- Verification status.
- Account privacy settings.
- Followers count.
- Following count.
- Posts count.
- Joined date.

Implement:
- Profile editing.
- Profile viewing.
- Follow/unfollow.
- Follow requests for private accounts.
- Followers list.
- Following list.
- Block/unblock.
- Mute/unmute.
- Profile search.

Ensure users cannot modify protected fields or other users' profiles without authorization.

# 6. Posts and Content Management

Implement a complete post management system.

Post types should accommodate the existing MyBuddy product, including:

- Text posts.
- Image posts.
- Video posts.
- Multiple-image posts.
- Posts containing links.
- Reposts.
- Posts with captions.
- Posts with hashtags.
- Posts mentioning other users.

Features:
- Create posts.
- Edit posts.
- Delete posts.
- Retrieve individual posts.
- Retrieve user posts.
- Share posts.
- Save/bookmark posts.
- Report posts.
- Pin posts if supported.
- Control post visibility.
- Support drafts if applicable.

Implement comments and nested replies.

Comment functionality:
- Create comments.
- Edit comments.
- Delete comments.
- Reply to comments.
- Like comments.
- React to comments.
- Retrieve comment threads.
- Paginate comments.

Ensure that engagement counts remain consistent.

Use database transactions where multiple related records must be updated together.

# 7. Likes and Reactions

Implement a scalable engagement system.

Support:
- Like/unlike.
- Multiple reaction types if supported by the existing product.
- Post reactions.
- Comment reactions.
- Reaction counts.
- Users who reacted.
- Duplicate reaction prevention.

Use unique database constraints to prevent duplicate reactions.

Use efficient queries instead of retrieving every reaction to calculate counts.

# 8. Following and Followers

Implement a complete social graph.

Features:
- Follow users.
- Unfollow users.
- Follow requests.
- Accept/reject follow requests.
- Followers list.
- Following list.
- Mutual followers.
- Suggested accounts.
- Blocked users.
- Muted users.

Implement efficient database queries and indexes.

Prevent:
- Following oneself.
- Duplicate follows.
- Following blocked accounts.
- Accessing private content without permission.

# 9. News Feed and Recommendation Engine

Build a production-quality social feed.

Use:

- NestJS for feed orchestration.
- PostgreSQL for content and relationships.
- Redis for caching and high-frequency feed operations.
- BullMQ for asynchronous feed processing.

Implement a hybrid feed architecture.

### Following feed

Prioritize posts from accounts the user follows.

### Discovery feed

Recommend relevant public content from users they do not necessarily follow.

### Feed ranking

Design an extensible ranking system that considers:

- Recency.
- User relationships.
- Engagement.
- Relevance.
- Content quality.
- User interests.
- Previous interactions.
- Content diversity.

Do not make engagement the only ranking signal.

### Feed performance

- Cursor-based pagination.
- Redis caching.
- Efficient SQL queries.
- Avoid N+1 queries.
- Batch-load related user and engagement information.
- Support feed invalidation.
- Handle deleted and private content.
- Avoid duplicate posts.
- Respect blocks and mutes.

Implement a hybrid fan-out strategy:
- Fan-out on write for normal accounts where appropriate.
- Fan-out on read for accounts with very large audiences.
- Use BullMQ for asynchronous feed distribution.

Do not create an expensive feed-generation operation for every follower synchronously.

Keep feed-ranking logic separate from feed retrieval so it can evolve independently.

# 10. Real-Time Messaging — WebSockets

Implement real-time messaging using NestJS WebSocket Gateway and Socket.IO.

Features:
- One-to-one conversations.
- Group conversations if supported.
- Send and receive messages.
- Text messages.
- Image attachments.
- Video attachments.
- Message reactions.
- Message editing.
- Message deletion.
- Reply to messages.
- Typing indicators.
- Online/offline presence.
- Last seen.
- Message delivery status.
- Read receipts.
- Conversation history.
- Unread message counts.
- Conversation management.

Requirements:

- Authenticate WebSocket connections using Firebase ID tokens.
- Verify conversation membership before allowing access.
- Persist messages in PostgreSQL.
- Use Redis for cross-instance Socket.IO coordination when scaling horizontally.
- Handle reconnections.
- Prevent unauthorized room access.
- Implement message rate limiting.
- Avoid losing messages during temporary disconnections.

Use database persistence as the source of truth, not in-memory socket state.

# 11. Push Notifications — Firebase Cloud Messaging

Implement Firebase Cloud Messaging.

Support notifications for:

- New followers.
- Follow requests.
- Accepted follow requests.
- Post likes.
- Comments.
- Comment replies.
- Mentions.
- Reposts.
- New messages.
- Message requests.
- Relevant account activity.

Requirements:

- Store device tokens securely.
- Support multiple devices per user.
- Manage token refresh.
- Remove invalid or expired tokens.
- Respect notification preferences.
- Support notification categories.
- Support deep links to relevant application screens.
- Avoid duplicate notifications.

Send push notifications asynchronously using BullMQ.

Persist in-app notifications in PostgreSQL.

Do not send FCM requests directly inside critical post or messaging database transactions.

# 12. Images and Videos — Cloudflare R2

Migrate media storage to Cloudflare R2.

Use the S3-compatible API.

Implement a secure upload architecture.

### Upload workflow

1. Frontend requests an upload authorization from NestJS.
2. NestJS verifies the authenticated user.
3. Backend validates file type, size and permissions.
4. Backend generates a presigned upload URL.
5. Frontend uploads directly to Cloudflare R2.
6. Frontend confirms the upload.
7. Backend verifies the object and creates its database record.
8. Media processing jobs are queued when necessary.

Support:
- Profile pictures.
- Cover images.
- Post images.
- Post videos.
- Message attachments.
- Story media, if applicable.

### Image processing

Implement:
- Thumbnail generation.
- Image resizing.
- Image optimization.
- Multiple image variants.
- Appropriate metadata.

### Video processing

Design an asynchronous video-processing pipeline.

Support:
- Video validation.
- Thumbnail generation.
- Transcoding into browser-friendly formats.
- Multiple resolutions where appropriate.
- Video metadata.
- Processing status.
- Upload progress.
- Processing failure handling.

Use FFmpeg for video processing where appropriate.

### Security

- Never expose R2 credentials to the frontend.
- Validate MIME types and actual file content.
- Restrict upload sizes.
- Generate unique object keys.
- Prevent arbitrary file access.
- Use signed URLs or a controlled public delivery strategy.
- Implement orphaned upload cleanup.
- Consider malware scanning for uploaded files.

Preserve existing media during migration. Do not delete Firebase Storage objects until migration has been verified.

# 13. Background Jobs — BullMQ

Use Redis and BullMQ for asynchronous tasks.

Create dedicated job queues for:

1. Feed generation.
2. Notification delivery.
3. Email notifications.
4. Media processing.
5. Video transcoding.
6. Image processing.
7. Search indexing.
8. Analytics aggregation.
9. Scheduled cleanup.
10. Account deletion workflows.

Requirements:
- Retry failed jobs.
- Exponential backoff.
- Job prioritization.
- Idempotent processing.
- Job monitoring.
- Failed-job handling.
- Graceful worker shutdown.
- Configurable concurrency.

Ensure background jobs do not block HTTP requests.

# 14. Search

Initially use PostgreSQL full-text search and indexes.

Implement search for:
- Users.
- Usernames.
- Posts.
- Hashtags.
- Relevant public content.

Support:
- Search suggestions.
- Pagination.
- Search filters.
- Recent searches where appropriate.
- Popular hashtags.

Structure the search module so OpenSearch can be introduced later without rewriting the entire application.

Do not introduce OpenSearch until actual search volume or requirements justify it.

# 15. Analytics

Build an extensible analytics pipeline.

Track relevant events:
- User registrations.
- Active users.
- Posts created.
- Post impressions.
- Likes.
- Comments.
- Shares.
- Follows.
- Message activity.
- Video views.
- Engagement rates.

Implement:
- User activity analytics.
- Post performance analytics.
- Engagement metrics.
- Daily and monthly aggregates.
- Platform-wide metrics.

Do not execute expensive analytical queries on every user-facing request.

Use background aggregation jobs and appropriate indexes.

Avoid collecting unnecessary personal information.

# 16. API Design

Build a versioned REST API.

Use:

`/api/v1/`

Organize endpoints by module.

Example:

**Authentication and users**
- GET /api/v1/users/me
- PATCH /api/v1/users/me
- GET /api/v1/users/:username
- GET /api/v1/users/:id/followers
- GET /api/v1/users/:id/following

**Posts**
- POST /api/v1/posts
- GET /api/v1/posts/:id
- PATCH /api/v1/posts/:id
- DELETE /api/v1/posts/:id
- GET /api/v1/posts/:id/comments

**Feed**
- GET /api/v1/feed/following
- GET /api/v1/feed/discover

**Engagement**
- POST /api/v1/posts/:id/like
- DELETE /api/v1/posts/:id/like
- POST /api/v1/posts/:id/reactions

**Comments**
- POST /api/v1/posts/:id/comments
- PATCH /api/v1/comments/:id
- DELETE /api/v1/comments/:id
- POST /api/v1/comments/:id/replies

**Following**
- POST /api/v1/users/:id/follow
- DELETE /api/v1/users/:id/follow

**Messaging**
- GET /api/v1/conversations
- POST /api/v1/conversations
- GET /api/v1/conversations/:id/messages

**Notifications**
- GET /api/v1/notifications
- PATCH /api/v1/notifications/:id/read
- PATCH /api/v1/notifications/read-all

**Media**
- POST /api/v1/media/upload-url
- POST /api/v1/media/complete
- DELETE /api/v1/media/:id

These are suggested routes. Adapt them to existing frontend contracts where appropriate.

Use:
- DTO validation.
- Consistent error responses.
- Appropriate HTTP status codes.
- Swagger/OpenAPI documentation.
- Request pagination.
- Rate limiting.
- Authorization guards.
- API versioning.

# 17. Security and Production Readiness

Treat security as a fundamental requirement.

Implement:

- Firebase token verification.
- Role-based authorization.
- Input validation.
- SQL injection protection.
- XSS prevention.
- CSRF protection where applicable.
- Rate limiting.
- Upload validation.
- Secure HTTP headers.
- CORS configuration.
- Secrets management.
- Audit logging for sensitive actions.
- Account deletion.
- Privacy enforcement.
- Block and mute enforcement.
- Spam prevention.
- Abuse reporting.
- Secure WebSocket authentication.

Never trust frontend-supplied engagement counts, ownership information, permissions or identity.

Do not expose private information through API responses.

# 18. Frontend Integration

This is a backend rebuild, not permission to redesign the entire MyBuddy application.

Preserve:
- Existing UI.
- Existing branding.
- Existing navigation.
- Existing responsive layouts.
- Existing design system.
- Existing components.
- Existing user workflows.

Update frontend services and API integration to communicate with NestJS.

Replace Firebase Firestore-dependent social data operations with the new REST API where applicable.

Replace Firebase Storage uploads with Cloudflare R2 presigned uploads.

Keep Firebase Authentication and Firebase Cloud Messaging.

Implement:
- Loading states.
- Skeleton screens.
- Empty states.
- Error states.
- Optimistic updates where safe.
- Pagination.
- Retry behavior.
- Real-time updates.
- Proper cache invalidation.

Do not remove working functionality simply because it is not explicitly listed in this specification.

# 19. Testing

Implement a comprehensive testing strategy.

### Unit tests
- Authentication.
- User services.
- Post services.
- Comment services.
- Follow services.
- Feed ranking.
- Notification services.
- Messaging services.
- Media services.

### Integration tests
- PostgreSQL operations.
- Redis operations.
- Firebase authentication verification.
- Cloudflare R2 upload workflow.
- BullMQ processing.
- WebSocket communication.

### End-to-end tests
- User registration.
- Login.
- Profile editing.
- Creating posts.
- Uploading media.
- Following users.
- Liking posts.
- Commenting.
- Feed retrieval.
- Sending messages.
- Receiving notifications.

Test authorization boundaries and privacy rules, not just successful requests.

# 20. Deployment and Infrastructure

Create a Docker-compatible development and production environment.

Provide:
- PostgreSQL configuration.
- Redis configuration.
- NestJS API container.
- Background worker container.
- Database migration commands.
- Environment variable documentation.
- Health checks.
- Logging.
- Graceful shutdown.
- Production build scripts.

Provide a complete `.env.example` covering:

FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=

DATABASE_URL=

REDIS_URL=

R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET_NAME=
R2_PUBLIC_URL=

FCM configuration as required.

Never commit actual credentials.

Support separate development, staging and production environments.

# 21. Migration Strategy

The existing MyBuddy platform may already contain Firebase users, posts, comments, likes, followers and uploaded media.

Do not destroy existing data.

Implement a controlled migration.

Phase 1: Audit and document all existing Firebase collections and data structures.

Phase 2: Design PostgreSQL schema and migrations.

Phase 3: Implement Firebase authentication verification and user synchronization.

Phase 4: Build NestJS modules and PostgreSQL repositories.

Phase 5: Migrate existing social data with scripts that support batching, validation, retries and duplicate prevention.

Phase 6: Migrate media to R2 without breaking existing media URLs.

Phase 7: Update frontend API integrations.

Phase 8: Introduce Redis caching and BullMQ workers.

Phase 9: Introduce WebSocket messaging and real-time notifications.

Phase 10: Validate the migrated application and switch production traffic safely.

Where practical, use temporary compatibility adapters or dual-read verification during migration.

Do not introduce uncontrolled dual writes.

Maintain data integrity and provide rollback procedures.

Only retire old Firebase Firestore or Storage dependencies after verifying that the new implementation works and all required data has been migrated.

# 22. Development Rules

Follow these rules throughout implementation:

1. Inspect before modifying.
2. Reuse existing code where appropriate.
3. Avoid unnecessary dependencies.
4. Use TypeScript strictly.
5. Follow NestJS architectural conventions.
6. Keep controllers thin.
7. Put business logic in services.
8. Separate database access from business logic.
9. Use DTOs for request validation.
10. Avoid duplicated logic.
11. Use transactions where appropriate.
12. Use cursor pagination for large collections.
13. Avoid N+1 database queries.
14. Never hardcode credentials.
15. Never introduce mock implementations as finished production features.
16. Do not leave TODOs for essential functionality.
17. Maintain backward compatibility where practical.
18. Do not redesign unrelated frontend screens.
19. Do not remove existing features without documenting and justifying the change.
20. Run tests, linting and production builds after implementation.

# 23. Execution Plan

Work incrementally.

Do not attempt to replace the entire application in one uncontrolled operation.

Divide implementation into milestones:

**Milestone 1 — Architecture and audit**
- Inspect repository.
- Document current implementation.
- Produce architecture and migration plans.

**Milestone 2 — Backend foundation**
- NestJS modules.
- PostgreSQL.
- Redis.
- Firebase authentication.
- Database migrations.

**Milestone 3 — Social functionality**
- Profiles.
- Posts.
- Comments.
- Likes.
- Reactions.
- Followers.
- Feed.

**Milestone 4 — Media infrastructure**
- Cloudflare R2.
- Presigned uploads.
- Image processing.
- Video processing.

**Milestone 5 — Real-time functionality**
- WebSockets.
- Messaging.
- Presence.
- Read receipts.
- Notifications.

**Milestone 6 — Background processing**
- BullMQ.
- Feed jobs.
- Notification jobs.
- Media jobs.
- Analytics jobs.

**Milestone 7 — Search and analytics**
- PostgreSQL search.
- Analytics pipeline.
- Aggregations.

**Milestone 8 — Frontend migration**
- Replace old social data integrations.
- Preserve existing UI.
- Connect all new APIs.
- Validate all existing workflows.

**Milestone 9 — Production readiness**
- Security testing.
- Performance testing.
- Data migration verification.
- Deployment configuration.
- Documentation.

At the end of every milestone:
- Run relevant tests.
- Run linting.
- Run production builds.
- Fix discovered issues.
- Document completed functionality.
- Identify remaining work.

# 24. Final Deliverables

The completed project should include:

1. A fully functional NestJS backend.
2. PostgreSQL database schema and migrations.
3. Redis integration.
4. Firebase Authentication integration.
5. Firebase Cloud Messaging integration.
6. Cloudflare R2 media integration.
7. BullMQ background workers.
8. Real-time messaging infrastructure.
9. Social feed implementation.
10. Search implementation.
11. Analytics infrastructure.
12. Updated frontend API integrations.
13. Docker configuration.
14. `.env.example`.
15. Swagger API documentation.
16. Automated tests.
17. Database migration scripts.
18. Architecture documentation.
19. Deployment instructions.
20. Production migration and rollback documentation.

# IMPORTANT FINAL INSTRUCTION

The goal is not merely to create a new backend or generate boilerplate code.

The goal is to **successfully rebuild the existing MyBuddy social media platform around this new architecture while preserving its existing product identity, user experience, functionality and data.**

Prioritize correctness, security, maintainability, performance and data integrity.

Start by auditing the repository. Present the existing architecture, proposed architecture, migration risks and implementation milestones before making major changes.

Once the audit is complete, begin implementation milestone by milestone. Do not stop after generating a plan or scaffolding. Continue implementing, testing and integrating the actual functionality.

If an existing feature is not covered explicitly in this specification, inspect how it currently works and preserve it unless there is a clear technical reason to change it.