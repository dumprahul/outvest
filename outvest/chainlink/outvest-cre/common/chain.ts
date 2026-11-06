import {
  EVMClient, LAST_FINALIZED_BLOCK_NUMBER, TxStatus, bytesToHex, encodeCallMsg, getNetwork,
  prepareReportRequest, type Runtime,
} from '@chainlink/cre-sdk'
import {
  decodeFunctionResult, encodeFunctionData, zeroAddress, type Abi, type Hex,
} from 'viem'

export type ChainCfg = { chainSelectorName: string; gasLimit: string; receiver: string }

export function evmClient(chainSelectorName: string): EVMClient {
  const network = getNetwork({ chainFamily: 'evm', chainSelectorName })
  if (!network) throw new Error(`Unknown chain selector: ${chainSelectorName}`)
  return new EVMClient(network.chainSelector.selector)
}

/** Finalized read. Counts against ChainRead.CallLimit (15 per execution). */
export function read<T>(
  runtime: Runtime<unknown>, client: EVMClient, to: Hex, abi: Abi, functionName: string, args: unknown[] = [],
): T {
  const reply = client
    .callContract(runtime, {
      call: encodeCallMsg({ from: zeroAddress, to, data: encodeFunctionData({ abi, functionName, args } as never) }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result()
  return decodeFunctionResult({ abi, functionName, data: bytesToHex(reply.data) } as never) as T
}

export type WriteOutcome = { txHash: string; receiverStatus: string }

/** Sign the envelope as a CRE report and deliver it to the ReportReceiver via the forwarder. */
export function writeEnvelope(
  runtime: Runtime<unknown>, client: EVMClient, cfg: ChainCfg, envelope: Hex,
): WriteOutcome {
  const report = runtime.report(prepareReportRequest(envelope)).result()
  const res = client
    .writeReport(runtime, { receiver: cfg.receiver, report, gasConfig: { gasLimit: cfg.gasLimit } })
    .result()
  if (res.txStatus !== TxStatus.SUCCESS) throw new Error(res.errorMessage ?? `write status ${res.txStatus}`)
  if (!res.txHash) throw new Error('write succeeded without a transaction hash')
  // A receiver revert (wrong workflow id/owner, replay...) still returns SUCCESS for the tx.
  const receiverStatus = String(res.receiverContractExecutionStatus)
  return { txHash: bytesToHex(res.txHash), receiverStatus }
}

export const nowSec = (runtime: Runtime<unknown>): bigint => BigInt(Math.floor(runtime.now().getTime() / 1000))
