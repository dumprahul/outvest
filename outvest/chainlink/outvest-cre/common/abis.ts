import { parseAbi } from 'viem'

export const factoryAbi = parseAbi([
  'function campaignCount() view returns (uint256)',
  'function campaignAt(uint256 index) view returns (address)',
  'event VerifyRequested(address indexed vault, address indexed wallet, bytes32 indexed videoId, bytes32 challenge)',
])

export const vaultAbi = parseAbi([
  'function creators(uint256 offset, uint256 limit) view returns (address[])',
  'function videosOf(address wallet) view returns (bytes32[])',
  'function claimable(address wallet) view returns (uint256)',
  'function minPayout() view returns (uint256)',
  'function bindDeadline() view returns (uint64)',
  'function scheduleLength() view returns (uint256)',
  'function finalized() view returns (bool)',
  'function creatorCount() view returns (uint256)',
])
