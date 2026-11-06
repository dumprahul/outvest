import { z } from 'zod'

/** Marker for ids YouTube did not return (private/deleted/typo). Never reported onchain. */
export const MISSING = -1

const itemSchema = z.object({
  id: z.string(),
  snippet: z.object({ description: z.string().optional() }).optional(),
  statistics: z.object({ viewCount: z.string().optional() }).optional(),
})
const bodySchema = z.object({ items: z.array(itemSchema).default([]) })

export type YtItem = { id: string; description: string; views: number }

export function parseVideos(body: unknown): YtItem[] {
  const parsed = bodySchema.parse(body)
  return parsed.items.map((i) => {
    const raw = i.statistics?.viewCount
    // viewCount is a decimal string; hidden counts are omitted. Treat absent as missing.
    const views = raw !== undefined && /^\d{1,15}$/.test(raw) ? Number(raw) : MISSING
    return { id: i.id, description: i.snippet?.description ?? '', views }
  })
}

