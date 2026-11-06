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
 *
 * Env: FACTORY, YOUTUBE_API_KEY_VAR, RELAYER_PRIVATE_KEY (or PRIVATE_KEY), RPC_URL (optional)
 */
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
import { vaultAbi } from '../common/abis'

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
    console.log(`  dry-run OK: onReport would not revert (${(envelope.length - 2) / 2} report bytes)`)
    return
  }
  const hash = await wallet.writeContract({ address: receiver, abi: receiverAbi, functionName: 'onReport', args })
  const rc = await pub.waitForTransactionReceipt({ hash })
  console.log(`  tx ${hash} status=${rc.status}`)
  for (const log of rc.logs) {
    try {
      const ev = decodeEventLog({ abi: receiverAbi, data: log.data, topics: log.topics })
      if (ev.eventName === 'ReportAccepted') console.log(`  ReportAccepted type=${ev.args.rtype} seq=${ev.args.seq}`)
      if (ev.eventName === 'ReportRejected') {
        const reason = Buffer.from(ev.args.reason.slice(2), 'hex').toString().replace(/\0/g, '')
        console.log(`  ReportRejected type=${ev.args.rtype} reason=${reason}`)
      }
    } catch { /* not a receiver event */ }
  }
}

const nowSec = () => BigInt(Math.floor(Date.now() / 1000))

async function bind(factory: Hex, vault: Hex, wallet_: Hex) {
  const [videoId, challenge] = await pub.readContract({
    address: vault, abi: pendingAbi, functionName: 'pendingBinding', args: [wallet_],
  })
  const yt = bytes32ToVideoId(videoId)
  if (!yt) throw new Error('no pending binding for this wallet')
  const [item] = await ytVideos([yt], 'snippet,statistics')
  if (!item || item.views === MISSING) throw new Error(`YouTube did not return public stats for ${yt}`)
  if (!descriptionHasChallenge(item.description, challenge)) {
    console.log(`challenge NOT found in the description of ${yt}; nothing sent`)
    return
  }
  console.log(`challenge found on ${yt}; baseline views=${item.views}`)
  const env = encodeEnvelope(RType.BIND, vault, makeSeq(Date.now()), nowSec(),
    encodeBindPayload(wallet_, videoId, challenge, BigInt(item.views)))
  await send(factory, RType.BIND, env)
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
  if (kind === 'final') {
    const [fin, deadline, len] = await Promise.all([
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'finalized' }),
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'bindDeadline' }),
      pub.readContract({ address: vault, abi: vaultAbi, functionName: 'scheduleLength' }),
    ])
    if (fin) return console.log('already finalized')
    if (nowSec() < deadline + len) return console.log(`too early for FINAL (opens at ${deadline + len})`)
  }
  const { videos } = await collectVideos(vault)
  if (videos.length === 0) return console.log('no bound videos')
  if (kind === 'final' && videos.length > MAX_SNAPSHOT_ENTRIES) throw new Error('too many videos for one FINAL')
  const rtype = kind === 'snapshot' ? RType.SNAPSHOT : RType.FINAL
  let i = 0
  for (const part of chunk(videos, MAX_SNAPSHOT_ENTRIES)) {
    const items = new Map((await ytVideos(part.map((v) => v.yt), 'statistics')).map((x) => [x.id, x.views]))
    const ids: Hex[] = []; const vals: bigint[] = []
    for (const v of part) {
      const n = items.get(v.yt) ?? MISSING
      if (n === MISSING) { console.log(`  skip ${v.yt}: no public view count`); continue }
      ids.push(v.b32); vals.push(BigInt(n)); console.log(`  ${v.yt}: ${n} views`)
    }
    if (ids.length === 0) continue
    await send(factory, rtype, encodeEnvelope(rtype, vault, makeSeq(Date.now(), i++), nowSec(), encodeViewsPayload(ids, vals)))
  }
}

async function claim(factory: Hex, vault: Hex) {
  const minPayout = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'minPayout' })
  const { wallets } = await collectVideos(vault)
  const due: Hex[] = []
  for (const w of wallets) {
    const c = await pub.readContract({ address: vault, abi: vaultAbi, functionName: 'claimable', args: [w] })
    console.log(`  ${w}: claimable ${c}`)
    if (c >= minPayout) due.push(w)
  }
  if (due.length === 0) return console.log('nothing due')
  let i = 0
  for (const part of chunk(due, MAX_BATCH)) {
    await send(factory, RType.CLAIM, encodeEnvelope(RType.CLAIM, vault, makeSeq(Date.now(), i++), nowSec(), encodeClaimPayload(part)))
  }
}

const cmd = process.argv[2]
const factory = need(process.env.FACTORY, 'FACTORY') as Hex
const vault = need(arg('vault'), '--vault') as Hex
console.log(`${cmd}${dryRun ? ' (dry-run)' : ''} as ${account.address}`)
if (cmd === 'bind') await bind(factory, vault, need(arg('wallet'), '--wallet') as Hex)
else if (cmd === 'snapshot') await views(factory, vault, 'snapshot')
else if (cmd === 'final') await views(factory, vault, 'final')
else if (cmd === 'claim') await claim(factory, vault)
else throw new Error('usage: bind|snapshot|final|claim --vault 0x.. [--wallet 0x..] [--dry-run]')
