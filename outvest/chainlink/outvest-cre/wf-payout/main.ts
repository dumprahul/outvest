import { CronCapability, Runner, handler, type Runtime } from '@chainlink/cre-sdk'
import type { Hex } from 'viem'
import { vaultAbi } from '../common/abis'
import { type ChainCfg, evmClient, nowSec, read, writeEnvelope } from '../common/chain'
import { MAX_BATCH, RType, chunk, encodeClaimPayload, encodeEnvelope, makeSeq } from '../common/report'
import { Budget, creatorsOf, resolveVaults, type VaultsCfg } from '../common/vaults'

type Config = ChainCfg & VaultsCfg & { schedule: string }

/**
 * WF-4 payout keeper. Reads claimable() per creator, selects those at or above the vault's minPayout,
 * and sends CLAIM batches. The report carries wallets only; the vault decides every amount.
 */
const onCron = (runtime: Runtime<Config>): string => {
  const cfg = runtime.config
  const client = evmClient(cfg.chainSelectorName)
  const budget = new Budget()
  const nowMs = runtime.now().getTime()
  const ts = nowSec(runtime)
  const results: string[] = []

  for (const vault of resolveVaults(runtime, client, cfg, budget)) {
    if (!budget.take()) break
    const minPayout = read<bigint>(runtime, client, vault, vaultAbi, 'minPayout')
    const due: Hex[] = []
    for (const w of creatorsOf(runtime, client, vault, budget)) {
      if (!budget.take()) { runtime.log('read budget exhausted; rest next run'); break }
      if (read<bigint>(runtime, client, vault, vaultAbi, 'claimable', [w]) >= minPayout) due.push(w)
    }
    if (due.length === 0) { results.push(`${vault}: nothing due`); continue }
    chunk(due, MAX_BATCH).slice(0, 16).forEach((part, i) => {
      const envelope = encodeEnvelope(RType.CLAIM, vault, makeSeq(nowMs, i), ts, encodeClaimPayload(part))
      const out = writeEnvelope(runtime, client, cfg, envelope)
      runtime.log(`CLAIM ${vault} batch ${i}: ${part.length} wallets tx=${out.txHash} receiver=${out.receiverStatus}`)
      results.push(`${vault}: CLAIM ${part.length} wallets tx=${out.txHash}`)
    })
  }
  return JSON.stringify({ readsUsed: budget.used, results })
}

const initWorkflow = (config: Config) => [
  handler(new CronCapability().trigger({ schedule: config.schedule }), onCron),
]

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
main()
