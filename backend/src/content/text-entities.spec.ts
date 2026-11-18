import { extractEntities } from './text-entities';

describe('extractEntities', () => {
  it('finds hashtags, mentions and links', () => {
    const e = extractEntities('Hello @Ada and @bob_99! #SwiftUI #swiftui #Lagos2026 see https://example.com/a?b=1.');
    expect(e.hashtags).toEqual(['swiftui', 'lagos2026']);
    expect(e.mentions).toEqual(['ada', 'bob_99']);
    expect(e.links).toEqual(['https://example.com/a?b=1']);
  });

  it('ignores emails, numeric tags, URL fragments and too-short handles', () => {
    const e = extractEntities('mail me at ada@example.com, item #1, https://x.com/#anchor @ab');
    expect(e.mentions).toEqual([]);
    expect(e.hashtags).toEqual([]);
  });

  it('supports non-latin hashtags, including combining diacritics', () => {
    expect(extractEntities('#café #ẹ̀kọ́ #東京').hashtags).toEqual(['café', 'ẹ̀kọ́', '東京']);
  });

  it('handles empty input', () => {
    expect(extractEntities(null)).toEqual({ hashtags: [], mentions: [], links: [] });
  });
});
