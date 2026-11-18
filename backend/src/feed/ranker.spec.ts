import { Candidate, FOLLOWING_WEIGHTS, rank, score } from './ranker';

const now = new Date('2026-11-12T12:00:00Z');
const hoursAgo = (h: number) => new Date(now.getTime() - h * 3_600_000);

function candidate(over: Partial<Candidate>): Candidate {
  return {
    postId: Math.random().toString(36).slice(2),
    authorId: 'a',
    publishedAt: hoursAgo(1),
    source: 'FOLLOW',
    likes: 0,
    dislikes: 0,
    comments: 0,
    reposts: 0,
    hasMedia: false,
    authorAffinity: 0,
    interestOverlap: 0,
    openReports: 0,
    ...over,
  };
}

describe('feed ranker', () => {
  it('prefers newer posts when everything else is equal', () => {
    expect(score(candidate({ publishedAt: hoursAgo(1) }), FOLLOWING_WEIGHTS, now)).toBeGreaterThan(
      score(candidate({ publishedAt: hoursAgo(30) }), FOLLOWING_WEIGHTS, now),
    );
  });

  it('does not let engagement alone beat a fresh post from a close contact', () => {
    const viral = candidate({ source: 'FOLLOW', likes: 50_000, comments: 5_000, publishedAt: hoursAgo(36) });
    const friend = candidate({ source: 'CONTACT', authorAffinity: 10, publishedAt: hoursAgo(2) });
    expect(score(friend, FOLLOWING_WEIGHTS, now)).toBeGreaterThan(score(viral, FOLLOWING_WEIGHTS, now));
  });

  it('sinks reported and heavily disliked content', () => {
    const base = candidate({ likes: 5, dislikes: 5 });
    expect(score(candidate({ likes: 5, dislikes: 45 }), FOLLOWING_WEIGHTS, now)).toBeLessThan(score(base, FOLLOWING_WEIGHTS, now));
    expect(score(candidate({ openReports: 3 }), FOLLOWING_WEIGHTS, now)).toBeLessThan(score(candidate({}), FOLLOWING_WEIGHTS, now));
  });

  it('spreads out authors but never drops a candidate', () => {
    const items = [
      ...Array.from({ length: 5 }, (_, i) => candidate({ postId: `a${i}`, authorId: 'a', likes: 100, publishedAt: hoursAgo(0.1 * i) })),
      candidate({ postId: 'b0', authorId: 'b', publishedAt: hoursAgo(3) }),
      candidate({ postId: 'c0', authorId: 'c', publishedAt: hoursAgo(4) }),
    ];
    const ranked = rank(items, FOLLOWING_WEIGHTS, now);
    expect(ranked).toHaveLength(items.length);
    expect(new Set(ranked.map((r) => r.postId)).size).toBe(items.length);
    // Two of a's posts, then b and c are pulled forward; once only a's posts remain they follow in score order.
    expect(ranked.map((r) => r.authorId)).toEqual(['a', 'a', 'b', 'c', 'a', 'a', 'a']);
  });
});
