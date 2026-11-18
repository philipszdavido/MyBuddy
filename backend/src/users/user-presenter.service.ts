import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Relationship } from '../graph/relationship.service';
import { MediaPresenter } from '../media/media-presenter.service';
import { PrismaService } from '../prisma/prisma.service';

/** Compact author shape embedded in posts, comments, messages, notifications. */
export interface UserSummary {
  id: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
  isVerified: boolean;
}

export interface ProfileView extends UserSummary {
  bio: string | null;
  location: string | null;
  website: string | null;
  coverUrl: string | null;
  visibility: 'PUBLIC' | 'PRIVATE';
  followersCount: number;
  followingCount: number;
  postsCount: number;
  joinedAt: string;
  relationship: Omit<Relationship, 'blockedBy'> | null;
}

const mediaSelect = { status: true, variants: true } as const;

export const profileInclude = {
  avatar: { select: mediaSelect },
  cover: { select: mediaSelect },
  user: { select: { createdAt: true } },
} satisfies Prisma.UserProfileInclude;

type ProfileRow = Prisma.UserProfileGetPayload<{ include: typeof profileInclude }>;

@Injectable()
export class UserPresenter {
  constructor(
    private readonly prisma: PrismaService,
    private readonly media: MediaPresenter,
  ) {}

  /** Batch-loads summaries for many users in one query (avoids N+1 in lists). Missing ids are omitted. */
  async summaries(ids: Iterable<string>): Promise<Map<string, UserSummary>> {
    const unique = [...new Set(ids)];
    const map = new Map<string, UserSummary>();
    if (unique.length === 0) return map;
    const rows = await this.prisma.userProfile.findMany({
      where: { userId: { in: unique } },
      select: { userId: true, username: true, displayName: true, isVerified: true, avatar: { select: mediaSelect } },
    });
    await Promise.all(
      rows.map(async (r) => {
        map.set(r.userId, {
          id: r.userId,
          username: r.username,
          displayName: r.displayName,
          isVerified: r.isVerified,
          avatarUrl: await this.media.avatarUrl(r.avatar),
        });
      }),
    );
    return map;
  }

  async summary(id: string): Promise<UserSummary | null> {
    return (await this.summaries([id])).get(id) ?? null;
  }

  async profile(row: ProfileRow, relationship: Relationship | null): Promise<ProfileView> {
    const [avatarUrl, coverUrl] = await Promise.all([this.media.avatarUrl(row.avatar), this.media.avatarUrl(row.cover)]);
    let rel: ProfileView['relationship'] = null;
    if (relationship) {
      const { blockedBy: _hidden, ...visible } = relationship;
      rel = visible;
    }
    return {
      id: row.userId,
      username: row.username,
      displayName: row.displayName,
      avatarUrl,
      coverUrl,
      isVerified: row.isVerified,
      bio: row.bio,
      location: row.location,
      website: row.website,
      visibility: row.visibility,
      followersCount: row.followersCount,
      followingCount: row.followingCount,
      postsCount: row.postsCount,
      joinedAt: row.user.createdAt.toISOString(),
      relationship: rel,
    };
  }
}
