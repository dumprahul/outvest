import { describe, expect, test } from 'bun:test'
import { decodeAbiParameters, parseAbiParameters, type Hex } from 'viem'
import {
  MAX_SNAPSHOT_ENTRIES, RType, bytes32ToVideoId, chunk, descriptionHasChallenge, encodeBindPayload,
  encodeClaimPayload, encodeEnvelope, encodeViewsPayload, makeSeq, videoIdToBytes32,
} from './report'
import { parseVideos, MISSING } from './ytparse'

const VAULT = '0x1111111111111111111111111111111111111111' as Hex
const WALLET = '0x2222222222222222222222222222222222222222' as Hex

describe('videoId <-> bytes32', () => {
  test('left-aligned ASCII with 21 zero bytes', () => {
    const b = videoIdToBytes32('dQw4w9WgXcQ')
    expect(b).toBe(('0x645177347739576758635100000000000000000000000000000000000000' + '0000') as Hex)
    expect(b.length).toBe(66)
    expect(bytes32ToVideoId(b)).toBe('dQw4w9WgXcQ')
  })
  test('rejects bad ids and non-canonical bytes32', () => {
    expect(() => videoIdToBytes32('short')).toThrow()
    expect(bytes32ToVideoId('0x' + 'ff'.repeat(32))).toBeNull()
    expect(bytes32ToVideoId('0x' + '00'.repeat(32))).toBeNull()
  })
})

describe('report envelope matches ReportReceiver decoding', () => {
  test('envelope round trip', () => {
    const payload = encodeClaimPayload([WALLET])
    const env = encodeEnvelope(RType.CLAIM, VAULT, 7n, 1700000000n, payload)
    const [rtype, vault, seq, ts, p] = decodeAbiParameters(
      parseAbiParameters('uint8, address, uint64, uint64, bytes'), env)
    expect([rtype, vault.toLowerCase(), seq, ts, p]).toEqual([4, VAULT, 7n, 1700000000n, payload])
  })
  test('BIND payload is exactly 128 bytes (receiver requires length 128)', () => {
    const p = encodeBindPayload(WALLET, videoIdToBytes32('dQw4w9WgXcQ'), ('0x' + 'ab'.repeat(32)) as Hex, 12345n)
    expect((p.length - 2) / 2).toBe(128)
  })
  test('views payload bounds', () => {
    const id = videoIdToBytes32('dQw4w9WgXcQ')
    expect(() => encodeViewsPayload([], [])).toThrow()
    expect(() => encodeViewsPayload([id], [])).toThrow()
    const many = Array.from({ length: MAX_SNAPSHOT_ENTRIES + 1 }, () => id)
    expect(() => encodeViewsPayload(many, many.map(() => 1n))).toThrow()
    expect(() => encodeViewsPayload(many.slice(0, 50), many.slice(0, 50).map(() => 1n))).not.toThrow()
  })
  test('claim batch max 25', () => {
    expect(() => encodeClaimPayload(Array.from({ length: 26 }, () => WALLET))).toThrow()
  })
})

describe('seq / chunk', () => {
  test('seq strictly increases across ms and chunk indexes', () => {
    expect(makeSeq(1000, 1)).toBeGreaterThan(makeSeq(1000, 0))
    expect(makeSeq(1001, 0)).toBeGreaterThan(makeSeq(1000, 15))
    expect(() => makeSeq(1, 16)).toThrow()
    expect(makeSeq(Date.now() + 10 ** 12, 15)).toBeLessThan(2n ** 64n)
  })
  test('chunk', () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]])
  })
})

describe('challenge detection', () => {
  const c = '0x' + 'ab'.repeat(32)
  test('with and without 0x, any case', () => {
    expect(descriptionHasChallenge(`hi ${c}`, c)).toBe(true)
    expect(descriptionHasChallenge(`hi ${c.slice(2).toUpperCase()} bye`, c)).toBe(true)
    expect(descriptionHasChallenge('nothing here', c)).toBe(false)
    expect(descriptionHasChallenge('x', '0x1234')).toBe(false)
  })
})

describe('YouTube parsing', () => {
  test('counts are strings; hidden/missing stats become MISSING', () => {
    const items = parseVideos({
      items: [
        { id: 'aaaaaaaaaaa', statistics: { viewCount: '1234567' }, snippet: { description: 'd' } },
        { id: 'bbbbbbbbbbb', statistics: {} },
        { id: 'ccccccccccc', statistics: { viewCount: 'NaN' } },
      ],
    })
    expect(items.map((i) => i.views)).toEqual([1234567, MISSING, MISSING])
    expect(parseVideos({}).length).toBe(0)
  })
})
