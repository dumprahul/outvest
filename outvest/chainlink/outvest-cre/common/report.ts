import { encodeAbiParameters, padHex, parseAbiParameters, stringToHex, type Hex } from 'viem'

export const RType = { BIND: 1, SNAPSHOT: 2, FINAL: 3, CLAIM: 4 } as const
export type RTypeValue = (typeof RType)[keyof typeof RType]

/** Contract limits (CampaignVault.MAX_SNAPSHOT_ENTRIES / MAX_BATCH). */
export const MAX_SNAPSHOT_ENTRIES = 50
export const MAX_BATCH = 25

const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/

/** 11-char YouTube id -> bytes32, ASCII left-aligned, 21 zero bytes after. */
export function videoIdToBytes32(id: string): Hex {
  if (!VIDEO_ID_RE.test(id)) throw new Error(`invalid YouTube video id: ${id}`)
  return padHex(stringToHex(id), { dir: 'right', size: 32 })
}

/** bytes32 -> 11-char YouTube id. Returns null when it is not canonical. */
export function bytes32ToVideoId(b: string): string | null {
  const hex = b.toLowerCase().replace(/^0x/, '')
  if (hex.length !== 64) return null
  const body = hex.slice(0, 22)
  if (hex.slice(22) !== '0'.repeat(42)) return null
  let s = ''
  for (let i = 0; i < 22; i += 2) s += String.fromCharCode(parseInt(body.slice(i, i + 2), 16))
  return VIDEO_ID_RE.test(s) ? s : null
}

export function encodeEnvelope(
  rtype: RTypeValue, vault: Hex, seq: bigint, ts: bigint, payload: Hex,
): Hex {
  return encodeAbiParameters(
    parseAbiParameters('uint8 rtype, address vault, uint64 seq, uint64 ts, bytes payload'),
    [rtype, vault, seq, ts, payload],
  )
}

export const encodeBindPayload = (wallet: Hex, videoId: Hex, challenge: Hex, baseline: bigint): Hex =>
  encodeAbiParameters(
    parseAbiParameters('address wallet, bytes32 videoId, bytes32 challenge, uint64 baselineViews'),
    [wallet, videoId, challenge, baseline],
  )

export const encodeViewsPayload = (ids: Hex[], views: bigint[]): Hex => {
  if (ids.length !== views.length) throw new Error('ids/views length mismatch')
  if (ids.length === 0 || ids.length > MAX_SNAPSHOT_ENTRIES) throw new Error('bad entry count')
  return encodeAbiParameters(parseAbiParameters('bytes32[] ids, uint64[] views'), [ids, views])
}

export const encodeClaimPayload = (wallets: Hex[]): Hex => {
  if (wallets.length === 0 || wallets.length > MAX_BATCH) throw new Error('bad wallet count')
  return encodeAbiParameters(parseAbiParameters('address[] wallets'), [wallets])
}

export function chunk<T>(xs: T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size))
  return out
}

/**
 * seq must strictly increase per (vault, type) and never repeat. DON time in ms,
 * times 16, leaves 16 slots for chunked reports inside one execution.
 */
export function makeSeq(nowMs: number, chunkIndex = 0): bigint {
  if (chunkIndex < 0 || chunkIndex > 15) throw new Error('chunkIndex 0..15')
  return BigInt(nowMs) * 16n + BigInt(chunkIndex)
}

/** Challenge is shown to the creator as 0x + 64 hex; accept it with or without the 0x. */
export function descriptionHasChallenge(description: string, challenge: string): boolean {
  const c = challenge.toLowerCase().replace(/^0x/, '')
  if (!/^[0-9a-f]{64}$/.test(c)) return false
  return description.toLowerCase().includes(c)
}
