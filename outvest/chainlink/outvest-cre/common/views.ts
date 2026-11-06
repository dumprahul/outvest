import type { Runtime } from '@chainlink/cre-sdk'
import type { Hex } from 'viem'
import { type ChainCfg, evmClient, nowSec, writeEnvelope } from './chain'
import { vaultAbi } from './abis'
import { read } from './chain'
import {
  MAX_SNAPSHOT_ENTRIES, RType, chunk, encodeEnvelope, encodeViewsPayload, makeSeq,
} from './report'
import { Budget, boundVideos, creatorsOf, resolveVaults, type VaultsCfg } from './vaults'
import { MISSING, fetchViews } from './youtube'

export type ViewsCfg = ChainCfg & VaultsCfg

/**
 * Shared by WF-2 (SNAPSHOT) and WF-3 (FINAL): read bound videos from each vault,
 * fetch public view counts with per-id consensus, and send one report per <=50 entries.
 */
export function runViewsReport(runtime: Runtime<ViewsCfg>, kind: 'SNAPSHOT' | 'FINAL'): string {
  const cfg = runtime.config
  const client = evmClient(cfg.chainSelectorName)
  const budget = new Budget()
  const apiKey = runtime.getSecret({ id: 'YOUTUBE_API_KEY' }).result().value
  const nowMs = runtime.now().getTime()
  const ts = nowSec(runtime)
  const rtype = kind === 'SNAPSHOT' ? RType.SNAPSHOT : RType.FINAL
  const results: string[] = []

  for (const vault of resolveVaults(runtime, client, cfg, budget)) {
    if (kind === 'FINAL') {
      if (!budget.take()) break
      const finalized = read<boolean>(runtime, client, vault, vaultAbi, 'finalized')
      if (finalized) { results.push(`${vault}: already finalized`); continue }
      if (!budget.take() || !budget.take()) break
      const deadline = read<bigint>(runtime, client, vault, vaultAbi, 'bindDeadline')
      const len = read<bigint>(runtime, client, vault, vaultAbi, 'scheduleLength')
      if (ts < deadline + len) { results.push(`${vault}: too early for FINAL`); continue }
    }
    const videos = boundVideos(runtime, client, vault, creatorsOf(runtime, client, vault, budget), budget)
    if (videos.length === 0) { results.push(`${vault}: no bound videos`); continue }

    // FINAL must be one report so the vault finalizes with a complete view set.
    if (kind === 'FINAL' && videos.length > MAX_SNAPSHOT_ENTRIES) {
      results.push(`${vault}: ${videos.length} videos exceeds one FINAL report; use finalizeFromLastSnapshot`)
      continue
    }

    chunk(videos, MAX_SNAPSHOT_ENTRIES).slice(0, 16).forEach((part, i) => {
      const views = fetchViews(runtime, part.map((v) => v.yt), apiKey)
      const ids: Hex[] = []
      const vals: bigint[] = []
      part.forEach((v, j) => {
        if (views[j] === MISSING) return // absent from the report => vault leaves it unchanged
        ids.push(v.b32)
        vals.push(BigInt(Math.trunc(views[j])))
      })
      if (ids.length === 0) { results.push(`${vault}: chunk ${i} had no readable videos`); return }
      const envelope = encodeEnvelope(rtype, vault, makeSeq(nowMs, i), ts, encodeViewsPayload(ids, vals))
      const out = writeEnvelope(runtime, client, cfg, envelope)
      runtime.log(`${kind} ${vault} chunk ${i}: ${ids.length} videos tx=${out.txHash} receiver=${out.receiverStatus}`)
      results.push(`${vault}: ${kind} ${ids.length} videos tx=${out.txHash}`)
    })
  }
  return JSON.stringify({ kind, readsUsed: budget.used, results })
}
