import { EVMClient, Runner, bytesToHex, getNetwork, handler, hexToBase64, type Runtime } from '@chainlink/cre-sdk'
import type { EVM_PB } from '@chainlink/cre-sdk/pb'
import { decodeEventLog, keccak256, toBytes, type Hex } from 'viem'
import { factoryAbi } from '../common/abis'
import { type ChainCfg, evmClient, nowSec, writeEnvelope } from '../common/chain'
import {
  RType, bytes32ToVideoId, descriptionHasChallenge, encodeBindPayload, encodeEnvelope, makeSeq,
} from '../common/report'
import { checkBinding } from '../common/youtube'

type Config = ChainCfg & { factory: string }

const VERIFY_TOPIC = keccak256(toBytes('VerifyRequested(address,address,bytes32,bytes32)'))

/**
 * WF-1 registration check. Trigger: factory VerifyRequested (creator called submitForVerification).
 * Confirms the challenge text is in the public video description, then reports BIND with the
 * baseline view count. Sends nothing when the challenge is absent.
 */
const onVerifyRequested = (runtime: Runtime<Config>, log: EVM_PB.Log): string => {
  const topics = log.topics.map((t: Uint8Array) => bytesToHex(t) as Hex)
  const ev = decodeEventLog({
    abi: factoryAbi, eventName: 'VerifyRequested', topics: topics as [Hex, ...Hex[]], data: bytesToHex(log.data),
  })
  const { vault, wallet, videoId, challenge } = ev.args
  const yt = bytes32ToVideoId(videoId)
  if (!yt) return JSON.stringify({ status: 'REJECTED', reason: 'non-canonical videoId' })

  const apiKey = runtime.getSecret({ id: 'YOUTUBE_API_KEY' }).result().value
  const check = checkBinding(runtime, yt, challenge, descriptionHasChallenge, apiKey)
  if (!check.found) {
    runtime.log(`BIND skipped for ${wallet}: challenge not found on ${yt}`)
    return JSON.stringify({ status: 'NO_CHALLENGE', vault, wallet, videoId: yt })
  }

  runtime.log(`challenge found on ${yt}; baseline views=${check.views}; sending BIND for ${wallet}`)
  const envelope = encodeEnvelope(
    RType.BIND, vault, makeSeq(runtime.now().getTime()), nowSec(runtime),
    encodeBindPayload(wallet, videoId, challenge, BigInt(Math.trunc(check.views))),
  )
  const out = writeEnvelope(runtime, evmClient(runtime.config.chainSelectorName), runtime.config, envelope)
  runtime.log(`BIND ${wallet} ${yt} baseline=${check.views} tx=${out.txHash} receiver=${out.receiverStatus}`)
  return JSON.stringify({ status: 'BIND_SENT', vault, wallet, videoId: yt, baseline: check.views, tx: out.txHash })
}

const initWorkflow = (config: Config) => {
  const network = getNetwork({ chainFamily: 'evm', chainSelectorName: config.chainSelectorName })
  if (!network) throw new Error(`Unknown chain selector: ${config.chainSelectorName}`)
  const client = new EVMClient(network.chainSelector.selector)
  return [
    handler(
      client.logTrigger({
        addresses: [hexToBase64(config.factory)],
        topics: [{ values: [hexToBase64(VERIFY_TOPIC)] }],
      }),
      onVerifyRequested,
    ),
  ]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
main()
