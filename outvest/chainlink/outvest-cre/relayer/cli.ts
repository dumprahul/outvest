/**
 * OutVest manual relayer ("demo mode").
 *
 * Stands in for the Chainlink CRE workflows while deploy access is unavailable. It builds the same report
 * envelopes (common/report.ts) from real YouTube data and calls ReportReceiver.onReport from the wallet
 * that was set as the factory's forwarder. Trust note: whoever holds this key is the oracle.
 *
 *   bun relayer/cli.ts bind     --vault 0x.. --wallet 0x.. [--dry-run]
 *   bun relayer/cli.ts snapshot --vault 0x.. [--dry-run]
 *   bun relayer/cli.ts final    --vault 0x.. [--dry-run]
 *   bun relayer/cli.ts claim    --vault 0x.. [--dry-run]
 *   bun relayer/cli.ts watch    [--vault 0x.. ...] [--dry-run]     <- runs everything by itself
 *
 * `watch` needs only FACTORY (+ keys). It discovers every campaign vault from the factory, answers each
 * VerifyRequested event (checks the YouTube description, sends BIND), posts SNAPSHOT views on a cadence,
 * CLAIMs what is due and FINALizes at the end. Every step is also appended to a JSONL log that the creator
 * page shows (RELAYER_LOG, default relayer/cre-log.jsonl).
 *
 * Env: FACTORY, YOUTUBE_API_KEY_VAR, RELAYER_PRIVATE_KEY (or PRIVATE_KEY), RPC_URL (optional)
 */
import * as nodeFs from 'node:fs'
// the project's type setup does not ship full node typings; this is the only fs use
const fs = nodeFs as unknown as {
  mkdirSync(p: string, o: { recursive: boolean }): void
  appendFileSync(p: string, d: string): void
}
import { dirname, resolve } from 'node:path'
import {
  createPublicClient, createWalletClient, decodeEventLog, defineChain, http, parseAbi,
  concatHex, padHex, type Hex,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import {
  MAX_BATCH, MAX_SNAPSHOT_ENTRIES, RType, bytes32ToVideoId, chunk, descriptionHasChallenge,
  encodeBindPayload, encodeClaimPayload, encodeEnvelope, encodeViewsPayload, makeSeq,
} from '../common/report'
import { MISSING, parseVideos } from '../common/ytparse'
import { factoryAbi as discoveryAbi, vaultAbi } from '../common/abis'

const arc = defineChain({
  id: 5042002, name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: { default: { http: [process.env.RPC_URL ?? 'https://rpc.testnet.arc.io'] } },
})

const factoryAbi = parseAbi([
  'function receiver() view returns (address)',
  'function workflowOwner() view returns (address)',
  'function wfBind() view returns (bytes32)',
  'function wfSnapshot() view returns (bytes32)',
  'function wfFinal() view returns (bytes32)',
  'function wfPayout() view returns (bytes32)',
  'function forwarder() view returns (address)',
])
const receiverAbi = parseAbi([
  'function onReport(bytes metadata, bytes report)',
  'event ReportAccepted(address indexed vault, uint8 indexed rtype, uint64 seq)',
  'event ReportRejected(address indexed vault, uint8 indexed rtype, bytes32 reason)',
])
const pendingAbi = parseAbi([
  'function pendingBinding(address) view returns (bytes32 videoId, bytes32 challenge, uint64 requestedAt, uint64 lastSubmitTs, uint32 nonce)',
])

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`)
  return i > 0 ? process.argv[i + 1] : undefined
}
const flag = (name: string) => process.argv.includes(`--${name}`)
const need = (v: string | undefined, what: string): string => {
  if (!v) throw new Error(`missing ${what}`)
  return v
}

const LOG_FILE = resolve(process.env.RELAYER_LOG ?? new URL('./cre-log.jsonl', import.meta.url).pathname)
type Ctx = { vault?: string; wallet?: string; step?: string }
let ctx: Ctx = {}
function say(msg: string, o: { level?: 'info' | 'ok' | 'warn' | 'error'; tx?: string } & Ctx = {}) {
  console.log(msg)
  try {
    fs.mkdirSync(dirname(LOG_FILE), { recursive: true })
    const { level, tx, ...c } = o
    fs.appendFileSync(LOG_FILE, JSON.stringify({ t: Date.now(), level: level ?? 'info', msg: msg.trim(), tx, ...ctx, ...c }) + '\n')
  } catch { /* logging must never stop the relayer */ }
}

const pk = (process.env.RELAYER_PRIVATE_KEY ?? process.env.PRIVATE_KEY) as Hex | undefined
const account = privateKeyToAccount(need(pk, 'RELAYER_PRIVATE_KEY') as Hex)
const pub = createPublicClient({ chain: arc, transport: http() })
const wallet = createWalletClient({ account, chain: arc, transport: http() })
const dryRun = flag('dry-run')

async function ytVideos(ids: string[], part: string) {
  const key = need(process.env.YOUTUBE_API_KEY_VAR, 'YOUTUBE_API_KEY_VAR')
  const url = `https://www.googleapis.com/youtube/v3/videos?part=${part}&id=${ids.join(',')}&maxResults=${ids.length}&key=${encodeURIComponent(key)}`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`YouTube HTTP ${res.status}`)
  return parseVideos(await res.json())
}

/** Same layout the forwarder produces: workflowId(32) | workflowName(10) | workflowOwner(20). */
async function metadataFor(factory: Hex, rtype: number): Promise<Hex> {
  const fn = ['', 'wfBind', 'wfSnapshot', 'wfFinal', 'wfPayout'][rtype] as 'wfBind'
  const [id, owner] = await Promise.all([
    pub.readContract({ address: factory, abi: factoryAbi, functionName: fn }),
    pub.readContract({ address: factory, abi: factoryAbi, functionName: 'workflowOwner' }),
  ])
  return concatHex([id, padHex('0x', { size: 10 }), owner])
}

async function send(factory: Hex, rtype: number, envelope: Hex): Promise<void> {
  const receiver = await pub.readContract({ address: factory, abi: factoryAbi, functionName: 'receiver' })
  const fwd = await pub.readContract({ address: factory, abi: factoryAbi, functionName: 'forwarder' })
  if (fwd.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error(`relayer ${account.address} is not this factory's forwarder (${fwd})`)
  }
  const args = [await metadataFor(factory, rtype), envelope] as const
  if (dryRun) {
    await pub.simulateContract({ address: receiver, abi: receiverAbi, functionName: 'onReport', args, account })
    say(`dry-run OK: onReport would not revert (${(envelope.length - 2) / 2} report bytes)`)
    return
  }
  const hash = await wallet.writeContract({ address: receiver, abi: receiverAbi, functionName: 'onReport', args })
  const rc = await pub.waitForTransactionReceipt({ hash })
  say(`sent report tx ${hash} (${rc.status})`, { tx: hash, level: rc.status === 'success' ? 'info' : 'error' })
  for (const log of rc.logs) {
    try {
      const ev = decodeEventLog({ abi: receiverAbi, data: log.data, topics: log.topics })
      if (ev.eventName === 'ReportAccepted') say(`ReportAccepted type=${ev.args.rtype} seq=${ev.args.seq}`, { level: 'ok', tx: hash })
      if (ev.eventName === 'ReportRejected') {
        const reason = Buffer.from(ev.args.reason.slice(2), 'hex').toString().replace(/\0/g, '')
        say(`ReportRejected type=${ev.args.rtype} reason=${reason}`, { level: 'warn', tx: hash })
      }
    } catch { /* not a receiver event */ }
  }
}

const nowSec = () => BigInt(Math.floor(Date.now() / 1000))

async function bind(factory: Hex, vault: Hex, wallet_: Hex): Promise<boolean> {
  ctx = { vault, wallet: wallet_, step: 'bind' }
  const [videoId, challenge] = await pub.readContract({
    address: vault, abi: pendingAbi, functionName: 'pendingBinding', args: [wallet_],
  })
  const yt = bytes32ToVideoId(videoId)
  if (!yt) { say('no pending binding for this wallet', { level: 'warn' }); return true }
  say(`checking YouTube video ${yt} for the challenge`)
  const [item] = await ytVideos([yt], 'snippet,statistics')
  if (!item || item.views === MISSING) throw new Error(`YouTube did not return public stats for ${yt}`)
  if (!descriptionHasChallenge(item.description, challenge)) {
    say(`challenge not in the description of ${yt} yet; will retry`, { level: 'warn' })
    return false
  }
  say(`challenge found on ${yt}; baseline views=${item.views}`, { level: 'ok' })
  const env = encodeEnvelope(RType.BIND, vault, makeSeq(Date.now()), nowSec(),
    encodeBindPayload(wallet_, videoId, challenge, BigInt(item.views)))
  await send(factory, RType.BIND, env)
  return true
}

async function collectVideos(vault: Hex) {
  const wallets = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'creators', args: [0n, 50n] })
  const out: { b32: Hex; yt: string }[] = []
  for (const w of wallets) {
    const ids = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'videosOf', args: [w] })
    for (const id of ids) { const yt = bytes32ToVideoId(id); if (yt) out.push({ b32: id, yt }) }
  }
  return { wallets: [...wallets] as Hex[], videos: out }
}

async function views(factory: Hex, vault: Hex, kind: 'snapshot' | 'final') {
  ctx = { vault, step: kind }
  if (kind === 'final') {
    const [fin, deadline, len] = await Promise.all([
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'finalized' }),
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'bindDeadline' }),
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'scheduleLength' }),
    ])
    if (fin) return say('already finalized')
    if (nowSec() < deadline + len) return say(`too early for FINAL (opens at ${deadline + len})`)
  }
  const { videos } = await collectVideos(vault)
  if (videos.length === 0) return say('no bound videos')
  if (kind === 'final' && videos.length > MAX_SNAPSHOT_ENTRIES) throw new Error('too many videos for one FINAL')
  const rtype = kind === 'snapshot' ? RType.SNAPSHOT : RType.FINAL
  let i = 0
  for (const part of chunk(videos, MAX_SNAPSHOT_ENTRIES)) {
    const items = new Map((await ytVideos(part.map((v) => v.yt), 'statistics')).map((x) => [x.id, x.views]))
    const ids: Hex[] = []; const vals: bigint[] = []
    for (const v of part) {
      const n = items.get(v.yt) ?? MISSING
      if (n === MISSING) { say(`skip ${v.yt}: no public view count`); continue }
      ids.push(v.b32); vals.push(BigInt(n)); say(`${v.yt}: ${n} views`)
    }
    if (ids.length === 0) continue
    await send(factory, rtype, encodeEnvelope(rtype, vault, makeSeq(Date.now(), i++), nowSec(), encodeViewsPayload(ids, vals)))
  }
}

async function claim(factory: Hex, vault: Hex) {
  ctx = { vault, step: 'claim' }
  const minPayout = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'minPayout' })
  const { wallets } = await collectVideos(vault)
  const due: Hex[] = []
  for (const w of wallets) {
    const c = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'claimable', args: [w] })
    if (c > 0n) say(`${w}: claimable ${c}`)
    if (c >= minPayout) due.push(w)
  }
  if (due.length === 0) return say('nothing due')
  let i = 0
  for (const part of chunk(due, MAX_BATCH)) {
    await send(factory, RType.CLAIM, encodeEnvelope(RType.CLAIM, vault, makeSeq(Date.now(), i++), nowSec(), encodeClaimPayload(part)))
  }
}

const cmd = process.argv[2]
const factory = need(process.env.FACTORY, 'FACTORY') as Hex

async function vaultsOf(): Promise<Hex[]> {
  const explicit = process.argv.flatMap((a, i) => (a === '--vault' ? [process.argv[i + 1]] : [])) as Hex[]
  if (explicit.length) return explicit
  const n = await pub.readContract({ address: factory, abi: discoveryAbi, functionName: 'campaignCount' })
  const out: Hex[] = []
  for (let i = 0n; i < n; i++) out.push(await pub.readContract({ address: factory, abi: discoveryAbi, functionName: 'campaignAt', args: [i] }))
  return out
}

async function watch() {
  const pollMs = Number(process.env.POLL_SECONDS ?? 10) * 1000
  const snapMs = Number(process.env.SNAPSHOT_MINUTES ?? 30) * 60_000
  const fwd = await pub.readContract({ address: factory, abi: factoryAbi, functionName: 'forwarder' })
  ctx = { step: 'start' }
  say(`CRE verifier online. factory ${factory}, relayer ${account.address}${dryRun ? ' (dry-run)' : ''}`, { level: 'ok' })
  if (fwd.toLowerCase() !== account.address.toLowerCase()) {
    say(`this key is not the factory's forwarder (${fwd}); reports would be rejected`, { level: 'error' })
    process.exit(1)
  }
  let cursor = (await pub.getBlockNumber()) - 3000n
  const open = new Map<string, { vault: Hex; wallet: Hex; tries: number }>() // unanswered bind requests
  const lastSnap = new Map<string, number>()
  let known = 0
  for (;;) {
    try {
      const vaults = await vaultsOf()
      if (vaults.length !== known) { ctx = { step: 'discover' }; say(`watching ${vaults.length} campaign vault(s)`); known = vaults.length }
      const head = await pub.getBlockNumber()
      if (head >= cursor) {
        const logs = await pub.getContractEvents({
          address: factory, abi: discoveryAbi, eventName: 'VerifyRequested', fromBlock: cursor, toBlock: head,
        })
        cursor = head + 1n
        for (const l of logs) {
          const { vault, wallet: w, videoId } = l.args
          if (!vault || !w || !videoId) continue
          const key = `${vault}:${w}:${l.args.challenge}`
          if (!open.has(key)) {
            ctx = { vault, wallet: w, step: 'request' }
            say(`verification requested for ${bytes32ToVideoId(videoId)} by ${w}`, { tx: l.transactionHash ?? undefined })
            open.set(key, { vault, wallet: w, tries: 0 })
          }
        }
      }
      for (const [key, r] of [...open]) {
        try {
          const done = await bind(factory, r.vault, r.wallet)
          if (done) open.delete(key)
          else if (++r.tries >= 180) { say('gave up after 30 minutes', { level: 'error' }); open.delete(key) }
        } catch (e) {
          ctx = { vault: r.vault, wallet: r.wallet, step: 'bind' }
          say(`bind failed: ${(e as Error).message.split('\n')[0]}`, { level: 'error' })
          if (++r.tries >= 30) open.delete(key)
        }
      }
      for (const v of vaults) {
        if (Date.now() - (lastSnap.get(v) ?? 0) < snapMs) continue
        lastSnap.set(v, Date.now())
        await views(factory, v, 'snapshot')
        await claim(factory, v)
        await views(factory, v, 'final')
      }
    } catch (e) {
      ctx = { step: 'loop' }
      say(`tick failed (will retry): ${(e as Error).message.split('\n')[0]}`, { level: 'warn' })
    }
    await new Promise((r) => setTimeout(r, pollMs))
  }
}

if (cmd === 'watch') await watch()
else {
  const vault = need(arg('vault'), '--vault') as Hex
  say(`${cmd}${dryRun ? ' (dry-run)' : ''} as ${account.address}`)
  if (cmd === 'bind') await bind(factory, vault, need(arg('wallet'), '--wallet') as Hex)
  else if (cmd === 'snapshot') await views(factory, vault, 'snapshot')
  else if (cmd === 'final') await views(factory, vault, 'final')
  else if (cmd === 'claim') await claim(factory, vault)
  else throw new Error('usage: watch | bind|snapshot|final|claim --vault 0x.. [--wallet 0x..] [--dry-run]')
}
