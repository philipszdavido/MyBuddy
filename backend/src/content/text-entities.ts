/**
 * Extracts hashtags, @mentions and links from user text. Pure and deterministic: the same text
 * always yields the same entities, so edits can diff old vs new.
 */
export interface TextEntities {
  /** lower-case, without '#', unique, in order of first appearance */
  hashtags: string[];
  /** lower-case usernames, without '@', unique */
  mentions: string[];
  /** http(s) URLs, unique */
  links: string[];
}

export const MAX_HASHTAGS = 30;
export const MAX_MENTIONS = 20;

// A tag/mention must start the text or follow whitespace/punctuation (so "email@ada.com" is not a mention).
const HASHTAG = /(?:^|[^\p{L}\p{M}\p{N}_&/])#([\p{L}\p{M}\p{N}_]{1,50})/gu;
const MENTION = /(?:^|[^\p{L}\p{N}_.@/])@([a-zA-Z0-9_.]{3,30})/gu;
const LINK = /\bhttps?:\/\/[^\s<>"']{1,2000}/giu;

function unique(values: string[], max: number): string[] {
  return [...new Set(values)].slice(0, max);
}

export function extractEntities(text: string | null | undefined): TextEntities {
  if (!text) return { hashtags: [], mentions: [], links: [] };
  const hashtags = [...text.matchAll(HASHTAG)]
    .map((m) => m[1].toLowerCase())
    .filter((t) => !/^\d+$/.test(t)); // "#1" is not a hashtag
  const mentions = [...text.matchAll(MENTION)].map((m) => m[1].toLowerCase().replace(/\.+$/, '')).filter((u) => u.length >= 3);
  const links = [...text.matchAll(LINK)].map((m) => m[0].replace(/[.,;:!?)\]]+$/, ''));
  return { hashtags: unique(hashtags, MAX_HASHTAGS), mentions: unique(mentions, MAX_MENTIONS), links: unique(links, 10) };
}
