/**
 * Feed ranking, separate from retrieval: retrieval decides *which* posts are candidates (and enforces
 * privacy); the ranker only orders them. Pure and deterministic, so it is unit-tested and can be replaced
 * (e.g. by a learned model) without touching SQL.
 *
 * Engagement is one signal among several and is log-damped, so viral posts cannot drown out
 * recent posts from close connections.
 */
export type CandidateSource = 'SELF' | 'FOLLOW' | 'CONTACT' | 'DISCOVER';

export interface Candidate {
  postId: string;
  authorId: string;
  publishedAt: Date;
  source: CandidateSource;
  likes: number;
  dislikes: number;
  comments: number;
  reposts: number;
  hasMedia: boolean;
  /** Viewer's recent interactions (reactions + comments) with this author. */
  authorAffinity: number;
  /** 0..1: share of the post's hashtags the viewer has engaged with. */
  interestOverlap: number;
  /** Open reports against the post. */
  openReports: number;
}

export interface RankWeights {
  halfLifeHours: number;
  relationship: Record<CandidateSource, number>;
  affinity: number;
  engagement: number;
  interest: number;
  media: number;
  /** Max posts from the same author in any window of `diversityWindow` consecutive items. */
  maxPerAuthorInWindow: number;
  diversityWindow: number;
}

export const FOLLOWING_WEIGHTS: RankWeights = {
  halfLifeHours: 18,
  relationship: { SELF: 0.3, CONTACT: 0.8, FOLLOW: 0.5, DISCOVER: 0 },
  affinity: 0.6,
  engagement: 0.4,
  interest: 0.3,
  media: 0.1,
  maxPerAuthorInWindow: 2,
  diversityWindow: 5,
};

export const DISCOVER_WEIGHTS: RankWeights = {
  halfLifeHours: 48,
  relationship: { SELF: 0, CONTACT: 0, FOLLOW: 0, DISCOVER: 0 },
  affinity: 0.3,
  engagement: 0.8,
  interest: 0.8,
  media: 0.2,
  maxPerAuthorInWindow: 1,
  diversityWindow: 6,
};

const clamp01 = (x: number) => Math.max(0, Math.min(1, x));

export function score(c: Candidate, w: RankWeights, now: Date): number {
  const ageHours = Math.max(0, (now.getTime() - c.publishedAt.getTime()) / 3_600_000);
  const recency = Math.pow(0.5, ageHours / w.halfLifeHours);
  const engagementRaw = c.likes + 2 * c.comments + 3 * c.reposts - 0.5 * c.dislikes;
  const engagement = clamp01(Math.log1p(Math.max(0, engagementRaw)) / Math.log1p(1000));
  const affinity = clamp01(Math.log1p(c.authorAffinity) / Math.log1p(20));
  const relevance =
    1 +
    w.relationship[c.source] +
    w.affinity * affinity +
    w.engagement * engagement +
    w.interest * clamp01(c.interestOverlap) +
    (c.hasMedia ? w.media : 0);
  // Quality: reported content and heavily disliked content sink.
  const total = c.likes + c.dislikes;
  const dislikeRatio = total >= 10 ? c.dislikes / total : 0;
  const quality = (1 / (1 + c.openReports)) * (1 - 0.7 * dislikeRatio);
  return recency * relevance * quality;
}

/**
 * Orders candidates by score, then applies a diversity pass: walking down the list, a post is deferred
 * while its author already has `maxPerAuthorInWindow` posts among the last `diversityWindow` picks.
 * Deferred posts are placed as soon as they fit (never dropped), so pagination stays complete.
 */
export function rank(candidates: Candidate[], w: RankWeights, now = new Date()): Candidate[] {
  const scored = candidates
    .map((c) => ({ c, s: score(c, w, now) }))
    .sort((a, b) => b.s - a.s || b.c.publishedAt.getTime() - a.c.publishedAt.getTime() || (a.c.postId < b.c.postId ? -1 : 1));

  const out: Candidate[] = [];
  const pending = scored.map((x) => x.c);
  while (pending.length) {
    const recent = out.slice(-w.diversityWindow);
    const idx = pending.findIndex((c) => recent.filter((r) => r.authorId === c.authorId).length < w.maxPerAuthorInWindow);
    out.push(pending.splice(idx === -1 ? 0 : idx, 1)[0]);
  }
  return out;
}
