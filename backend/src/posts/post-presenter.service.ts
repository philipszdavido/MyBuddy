import { Injectable } from '@nestjs/common';
import { PostAudience, PostStatus, ReactionType } from '@prisma/client';
import { extractEntities } from '../content/text-entities';
import { RelationshipService } from '../graph/relationship.service';
import { MediaPresenter, MediaView } from '../media/media-presenter.service';
import { PrismaService } from '../prisma/prisma.service';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';

export type PostKind = 'text' | 'image' | 'video' | 'gallery' | 'repost' | 'quote';

export interface PostView {
  id: string;
  kind: PostKind;
  author: UserSummary;
  text: string | null;
  audience: PostAudience;
  status: PostStatus;
  media: MediaView[];
  hashtags: string[];
  mentions: string[];
  links: string[];
  isPinned: boolean;
  counts: { likes: number; dislikes: number; comments: number; reposts: number; shares: number; saves: number };
  viewer: { reaction: ReactionType | null; saved: boolean; reposted: boolean; canEdit: boolean };
  /** Original post of a repost/quote. `null` with repostUnavailable=true when deleted or not visible to the viewer. */
  repostOf: PostView | null;
  repostUnavailable: boolean;
  publishedAt: string | null;
  editedAt: string | null;
  createdAt: string;
}

const postSelect = {
  id: true, authorId: true, text: true, audience: true, status: true, repostOfId: true, isPinned: true,
  likeCount: true, dislikeCount: true, commentCount: true, repostCount: true, shareCount: true, saveCount: true,
  publishedAt: true, editedAt: true, createdAt: true, deletedAt: true,
  media: {
    orderBy: { position: 'asc' as const },
    select: { media: { select: { id: true, kind: true, status: true, width: true, height: true, durationMs: true, blurhash: true, variants: true } } },
  },
} as const;

@Injectable()
export class PostPresenter {
  constructor(
    private readonly prisma: PrismaService,
    private readonly users: UserPresenter,
    private readonly media: MediaPresenter,
    private readonly relationships: RelationshipService,
  ) {}

  /**
   * Builds views for `ids` in the given order. Callers must already have checked visibility of the
   * listed posts; embedded originals (reposts) are visibility-checked here. Missing/deleted ids are dropped.
   */
  async present(viewerId: string, ids: string[]): Promise<PostView[]> {
    if (ids.length === 0) return [];
    const posts = await this.prisma.post.findMany({ where: { id: { in: ids }, deletedAt: null }, select: postSelect });
    const originalIds = [...new Set(posts.map((p) => p.repostOfId).filter((x): x is string => !!x))];
    const visibleOriginals = originalIds.length ? await this.visibleIds(viewerId, originalIds) : new Set<string>();
    const originals = visibleOriginals.size
      ? await this.prisma.post.findMany({ where: { id: { in: [...visibleOriginals] }, deletedAt: null }, select: postSelect })
      : [];
    const all = [...posts, ...originals];
    const allIds = all.map((p) => p.id);

    const [authors, reactions, saves, reposts] = await Promise.all([
      this.users.summaries(all.map((p) => p.authorId)),
      this.prisma.postReaction.findMany({ where: { userId: viewerId, postId: { in: allIds } }, select: { postId: true, type: true } }),
      this.prisma.savedPost.findMany({ where: { userId: viewerId, postId: { in: allIds } }, select: { postId: true } }),
      this.prisma.post.findMany({ where: { authorId: viewerId, repostOfId: { in: allIds }, deletedAt: null }, select: { repostOfId: true } }),
    ]);
    const reactionBy = new Map(reactions.map((r) => [r.postId, r.type]));
    const saved = new Set(saves.map((s) => s.postId));
    const reposted = new Set(reposts.map((r) => r.repostOfId));

    const build = async (p: (typeof all)[number], nested: PostView | null, unavailable: boolean): Promise<PostView | null> => {
      const author = authors.get(p.authorId);
      if (!author) return null;
      const visibility = p.audience === 'PUBLIC' ? 'public' : 'private';
      const media = await Promise.all(p.media.map((m) => this.media.present(m.media, visibility)));
      const entities = extractEntities(p.text);
      const kind: PostKind = p.repostOfId
        ? (p.text || media.length ? 'quote' : 'repost')
        : media.length > 1 ? 'gallery' : media[0]?.kind === 'VIDEO' ? 'video' : media.length === 1 ? 'image' : 'text';
      return {
        id: p.id,
        kind,
        author,
        text: p.text,
        audience: p.audience,
        status: p.status,
        media,
        hashtags: entities.hashtags,
        mentions: entities.mentions,
        links: entities.links,
        isPinned: p.isPinned,
        counts: { likes: p.likeCount, dislikes: p.dislikeCount, comments: p.commentCount, reposts: p.repostCount, shares: p.shareCount, saves: p.saveCount },
        viewer: { reaction: reactionBy.get(p.id) ?? null, saved: saved.has(p.id), reposted: reposted.has(p.id), canEdit: p.authorId === viewerId },
        repostOf: nested,
        repostUnavailable: unavailable,
        publishedAt: p.publishedAt?.toISOString() ?? null,
        editedAt: p.editedAt?.toISOString() ?? null,
        createdAt: p.createdAt.toISOString(),
      };
    };

    const originalViews = new Map<string, PostView>();
    for (const o of originals) {
      const view = await build(o, null, false);
      if (view) originalViews.set(o.id, view);
    }
    const byId = new Map(posts.map((p) => [p.id, p]));
    const out: PostView[] = [];
    for (const id of ids) {
      const p = byId.get(id);
      if (!p) continue;
      const nested = p.repostOfId ? originalViews.get(p.repostOfId) ?? null : null;
      const view = await build(p, nested, !!p.repostOfId && !nested);
      if (view) out.push(view);
    }
    return out;
  }

  async presentOne(viewerId: string, id: string): Promise<PostView | null> {
    return (await this.present(viewerId, [id]))[0] ?? null;
  }

  /** Subset of `ids` the viewer may see (one query). */
  async visibleIds(viewerId: string, ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) return new Set();
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>`
      SELECT p.id FROM posts p WHERE p.id = ANY(${ids}::uuid[]) AND ${this.relationships.visiblePostSql(viewerId)}`;
    return new Set(rows.map((r) => r.id));
  }
}
