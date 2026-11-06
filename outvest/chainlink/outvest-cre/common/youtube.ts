import {
  ConsensusAggregationByFields, HTTPClient, identical, median, ok, json,
  type NodeRuntime, type Runtime,
} from '@chainlink/cre-sdk'
import { MISSING, parseVideos, type YtItem } from './ytparse'

export { MISSING, parseVideos }
export type { YtItem }

const API = 'https://www.googleapis.com/youtube/v3/videos'
const SLOTS = 50

const urlFor = (ids: string[], part: string, key: string) =>
  `${API}?part=${part}&id=${ids.join(',')}&key=${encodeURIComponent(key)}&maxResults=${ids.length}`

function fetchItems(node: NodeRuntime<unknown>, ids: string[], part: string, key: string): YtItem[] {
  const res = new HTTPClient()
    .sendRequest(node, { url: urlFor(ids, part, key), method: 'GET' })
    .result()
  if (!ok(res)) throw new Error(`YouTube HTTP ${res.statusCode}`)
  return parseVideos(json(res))
}

type SlotMap = Record<string, number>
const slotKeys = Array.from({ length: SLOTS }, (_, i) => `v${i}`)

/**
 * View counts for up to 50 ids with per-id median consensus across DON nodes.
 * The aggregator has fixed fields, so ids map to slots v0..v49.
 * Returns MISSING for ids YouTube did not return.
 */
export function fetchViews(runtime: Runtime<unknown>, ids: string[], apiKey: string): number[] {
  if (ids.length === 0 || ids.length > SLOTS) throw new Error('fetchViews: 1..50 ids')
  const agg = ConsensusAggregationByFields<SlotMap>(
    Object.fromEntries(slotKeys.map((k) => [k, median])) as never,
  )
  const out = runtime
    .runInNodeMode((node: NodeRuntime<unknown>, key: string): SlotMap => {
      const byId = new Map(fetchItems(node, ids, 'statistics', key).map((i) => [i.id, i.views]))
      return Object.fromEntries(slotKeys.map((k, i) => [k, i < ids.length ? (byId.get(ids[i]) ?? MISSING) : MISSING]))
    }, agg)(apiKey)
    .result()
  return ids.map((_, i) => out[slotKeys[i]])
}

export type BindCheck = { found: boolean; views: number }

/** Does the video's description contain the challenge, and what are its views right now. */
export function checkBinding(
  runtime: Runtime<unknown>, videoId: string, challenge: string,
  matches: (description: string, challenge: string) => boolean, apiKey: string,
): BindCheck {
  const agg = ConsensusAggregationByFields<BindCheck>({ found: identical, views: median })
  return runtime
    .runInNodeMode((node: NodeRuntime<unknown>, key: string): BindCheck => {
      const item = fetchItems(node, [videoId], 'snippet,statistics', key).find((i) => i.id === videoId)
      if (!item || item.views === MISSING) return { found: false, views: 0 }
      return { found: matches(item.description, challenge), views: item.views }
    }, agg)(apiKey)
    .result()
}
