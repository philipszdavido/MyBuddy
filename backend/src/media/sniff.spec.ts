import { sniff } from './sniff';

const pad = (b: number[]) => Buffer.concat([Buffer.from(b), Buffer.alloc(16)]);
const ftyp = (brand: string) => Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftyp' + brand, 'latin1'), Buffer.alloc(16)]);

describe('sniff', () => {
  it('recognises allowed formats from magic bytes', () => {
    expect(sniff(pad([0xff, 0xd8, 0xff, 0xe0]))).toBe('image/jpeg');
    expect(sniff(pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('image/png');
    expect(sniff(Buffer.concat([Buffer.from('RIFF\0\0\0\0WEBP', 'latin1'), Buffer.alloc(8)]))).toBe('image/webp');
    expect(sniff(ftyp('heic'))).toBe('image/heic');
    expect(sniff(ftyp('isom'))).toBe('video/mp4');
    expect(sniff(ftyp('qt  '))).toBe('video/quicktime');
  });

  it('rejects everything else, whatever the file claims to be', () => {
    expect(sniff(Buffer.from('<?xml version="1.0"?><svg/>....'))).toBeNull(); // SVG can carry script
    expect(sniff(Buffer.from('%PDF-1.7 .............'))).toBeNull();
    expect(sniff(pad([0x4d, 0x5a]))).toBeNull(); // Windows executable
    expect(sniff(Buffer.from([0xff, 0xd8]))).toBeNull(); // too short
  });
});
