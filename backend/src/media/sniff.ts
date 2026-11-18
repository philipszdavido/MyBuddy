/**
 * Identifies a file from its first bytes. The client-declared Content-Type is never trusted: an upload
 * is accepted only when its real format is in the allow-list for its purpose.
 */
export type SniffedType = 'image/jpeg' | 'image/png' | 'image/webp' | 'image/heic' | 'video/mp4' | 'video/quicktime';

const ascii = (buf: Buffer, start: number, end: number) => buf.subarray(start, end).toString('latin1');

export function sniff(buf: Buffer): SniffedType | null {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (ascii(buf, 0, 4) === 'RIFF' && ascii(buf, 8, 12) === 'WEBP') return 'image/webp';
  // ISO base media file: [size][ftyp][major brand]
  if (ascii(buf, 4, 8) === 'ftyp') {
    const brand = ascii(buf, 8, 12);
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(brand)) return 'image/heic';
    if (brand === 'qt  ') return 'video/quicktime';
    if (['isom', 'iso2', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V ', 'dash', '3gp4', '3gp5'].includes(brand)) return 'video/mp4';
  }
  return null;
}
