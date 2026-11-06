import type { EVMClient, Runtime } from '@chainlink/cre-sdk'
import type { Hex } from 'viem'
import { factoryAbi, vaultAbi } from './abis'
import { read } from './chain'
import { bytes32ToVideoId } from './report'

/** ChainRead.CallLimit is 15 per execution; stay under it and degrade gracefully. */
export const READ_BUDGET = 15

export class Budget {
  used = 0
  constructor(readonly limit = READ_BUDGET) {}
  take(): boolean {
    if (this.used >= this.limit) return false
    this.used++
    return true
  }
}

export type VaultsCfg = { factory: string; vaults?: string[]; maxCampaigns?: number }

/** Explicit vault list wins; otherwise the newest `maxCampaigns` campaigns from the factory. */
export function resolveVaults(runtime: Runtime<unknown>, client: EVMClient, cfg: VaultsCfg, b: Budget): Hex[] {
  if (cfg.vaults && cfg.vaults.length > 0) return cfg.vaults as Hex[]
  if (!b.take()) return []
  const count = read<bigint>(runtime, client, cfg.factory as Hex, factoryAbi, 'campaignCount')
  const n = Math.min(Number(count), cfg.maxCampaigns ?? 1)
  const out: Hex[] = []
  for (let i = 0; i < n; i++) {
    if (!b.take()) break
    out.push(read<Hex>(runtime, client, cfg.factory as Hex, factoryAbi, 'campaignAt', [count - 1n - BigInt(i)]))
  }
  return out
}

export function creatorsOf(runtime: Runtime<unknown>, client: EVMClient, vault: Hex, b: Budget): Hex[] {
  if (!b.take()) return []
  return [...read<readonly Hex[]>(runtime, client, vault, vaultAbi, 'creators', [0n, 50n])]
}

/** Bound video ids (as bytes32 + 11-char id) across the creators we have read budget for. */
export function boundVideos(
  runtime: Runtime<unknown>, client: EVMClient, vault: Hex, wallets: Hex[], b: Budget,
): { b32: Hex; yt: string }[] {
  const out: { b32: Hex; yt: string }[] = []
  for (const w of wallets) {
    if (!b.take()) {
      runtime.log(`read budget exhausted before ${w}; remaining creators wait for the next run`)
      break
    }
    for (const id of read<readonly Hex[]>(runtime, client, vault, vaultAbi, 'videosOf', [w])) {
      const yt = bytes32ToVideoId(id)
      if (yt) out.push({ b32: id, yt })
    }
  }
  return out
}
