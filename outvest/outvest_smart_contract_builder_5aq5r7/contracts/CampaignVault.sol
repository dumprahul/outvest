// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ScheduleLib} from "./ScheduleLib.sol";
import {ICampaignFactory} from "./interfaces/ICampaignFactory.sol";
import {ReportReasons} from "./interfaces/IReceiver.sol";

/// @notice Immutable USDC escrow. Requires a conventional, non-rebasing, non-fee-on-transfer USDC token.
contract CampaignVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SNAPSHOT_ENTRIES = 50;
    uint256 public constant MAX_BATCH = 25;
    uint256 public constant MAX_VIDEOS = 10;
    uint256 public constant MAX_PAGE = 50;
    uint256 private constant BUCKETS = 7;
    uint256 private constant PPM = 1_000_000;
    uint256 public constant MAX_ALLOWANCE_WINDOW = 14 days;
    uint256 public constant VERIFY_COOLDOWN = 10 minutes;
    /// @notice Upper bound on the instant payout released when a creator's first video is bound (10% of the cap).
    uint32 public constant MAX_UPFRONT_PPM = 100_000;

    struct Params {
        address brand;
        address usdc;
        uint64 bindDeadline;
        uint256 ratePerThousand;
        uint256 capPerCreator;
        uint32 maxCreators;
        uint8 maxVideosPerCreator;
        uint32 bucketLen;
        uint64 maxGrowthPerDay;
        uint64 staleAfter;
        uint64 deadmanTimeout;
        uint256 minPayout;
        uint32 upfrontPpm;
        ScheduleLib.Segment[] schedule;
    }

    struct Creator {
        bool bound;
        bool settled;
        uint64 boundAt;
        uint16 videoCount;
        uint128 paid;
        uint128 remaining;
        uint128 creditedViews;
        uint128 upfront;
        bytes32[10] videoIds;
    }

    struct VideoState {
        address creator;
        uint64 baseline;
        uint64 credited;
        uint64 lastUpdateTs;
        uint64[7] bucketMin;
        uint32[7] bucketEpoch;
    }

    struct PendingBind {
        bytes32 videoId;
        bytes32 challenge;
        uint64 requestedAt;
        uint32 nonce;
        uint64 lastSubmitTs;
    }

    address public immutable brand;
    IERC20 public immutable usdc;
    address public immutable receiver;
    address public immutable factory;
    bytes32 public immutable rulesHash;
    uint64 public immutable bindDeadline;
    uint256 public immutable ratePerThousand;
    uint256 public immutable capPerCreator;
    uint32 public immutable maxCreators;
    uint8 public immutable maxVideosPerCreator;
    uint32 public immutable bucketLen;
    uint64 public immutable maxGrowthPerDay;
    uint64 public immutable staleAfter;
    uint64 public immutable deadmanTimeout;
    uint256 public immutable minPayout;
    uint32 public immutable upfrontPpm;
    uint256 public immutable scheduleLength;

    uint256 public totalFunded;
    uint256 public liability;
    uint256 public totalPaid;
    uint256 public creatorCount;
    uint256 public settledCount;
    bool public finalized;
    uint64 public finalizedAt;
    uint64 public lastSnapshotTs;

    ScheduleLib.Segment[] private _schedule;
    address[] private creatorList;
    mapping(address => Creator) private _creator;
    mapping(bytes32 => VideoState) private _video;
    mapping(bytes32 => address) public videoOwner;
    mapping(address => PendingBind) public pendingBinding;

    error NotReceiver();
    error InvalidParams();
    error InvalidVideoId();
    error BindingClosed();
    error NoPendingBinding();
    error VideoAlreadyOwned();
    error VideoLimit();
    error Cooldown();
    error CampaignFinalized();
    error TooEarly();
    error NotFinalized();
    error NotBound();
    error InvalidPage();
    error UnsupportedToken();

    event Funded(address indexed funder, uint256 amount);
    event BindingRequested(address indexed wallet, bytes32 indexed videoId, bytes32 challenge);
    event Bound(address indexed wallet, bytes32 indexed videoId, uint64 baselineViews, uint64 boundAt);
    event SnapshotApplied(uint64 indexed timestamp, uint256 entries, bool finalReport);
    event EntrySkipped(bytes32 indexed videoId, bytes32 reason);
    event Paid(address indexed wallet, uint256 amount);
    event PayoutFailed(address indexed wallet, uint256 amount);
    event Finalized(uint64 at, bool deadman);
    event Settled(address indexed wallet, uint256 finalEarned, uint256 remaining);
    event Swept(address indexed brand, uint256 amount);

    modifier onlyReceiver() {
        if (msg.sender != receiver) revert NotReceiver();
        _;
    }

    constructor(Params memory p, address receiver_, address factory_, bytes32 rulesHash_) {
        ScheduleLib.validate(p.schedule);
        if (p.brand == address(0) || p.brand == address(this) || p.usdc.code.length == 0
            || receiver_ == address(0) || factory_ == address(0) || p.bindDeadline <= block.timestamp
            || p.ratePerThousand == 0 || p.ratePerThousand > type(uint128).max
            || p.capPerCreator == 0 || p.capPerCreator > type(uint128).max
            || p.maxCreators == 0 || p.maxVideosPerCreator == 0 || p.maxVideosPerCreator > MAX_VIDEOS
            || p.bucketLen < 1 hours || p.bucketLen > 7 days
            || p.staleAfter < 1 days || p.deadmanTimeout == 0 || p.upfrontPpm > MAX_UPFRONT_PPM) revert InvalidParams();
        brand = p.brand;
        usdc = IERC20(p.usdc);
        receiver = receiver_;
        factory = factory_;
        rulesHash = rulesHash_;
        bindDeadline = p.bindDeadline;
        ratePerThousand = p.ratePerThousand;
        capPerCreator = p.capPerCreator;
        maxCreators = p.maxCreators;
        maxVideosPerCreator = p.maxVideosPerCreator;
        bucketLen = p.bucketLen;
        maxGrowthPerDay = p.maxGrowthPerDay;
        staleAfter = p.staleAfter;
        deadmanTimeout = p.deadmanTimeout;
        minPayout = p.minPayout;
        upfrontPpm = p.upfrontPpm;
        scheduleLength = p.schedule[p.schedule.length - 1].start;
        lastSnapshotTs = uint64(block.timestamp);
        for (uint256 i; i < 8; ++i) {
            if (i == p.schedule.length) break;
            _schedule.push(p.schedule[i]);
        }
    }

    function fund(uint256 amount) external nonReentrant {
        if (finalized) revert CampaignFinalized();
        uint256 beforeBalance = usdc.balanceOf(address(this));
        totalFunded += amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        if (usdc.balanceOf(address(this)) != beforeBalance + amount) revert UnsupportedToken();
        emit Funded(msg.sender, amount);
    }

    function requestBinding(bytes32 videoId) external nonReentrant returns (bytes32 challenge) {
        if (block.timestamp >= bindDeadline || finalized) revert BindingClosed();
        if (!_validVideoId(videoId)) revert InvalidVideoId();
        if (videoOwner[videoId] != address(0)) revert VideoAlreadyOwned();
        if (_creator[msg.sender].videoCount >= maxVideosPerCreator) revert VideoLimit();
        PendingBind storage p = pendingBinding[msg.sender];
        uint32 nonce = p.nonce;
        challenge = keccak256(abi.encode(address(this), msg.sender, videoId, nonce, block.chainid));
        p.videoId = videoId;
        p.challenge = challenge;
        p.requestedAt = uint64(block.timestamp);
        p.nonce = nonce + 1;
        // Preserve lastSubmitTs across overwritten requests.
        emit BindingRequested(msg.sender, videoId, challenge);
    }

    function submitForVerification() external nonReentrant {
        PendingBind storage p = pendingBinding[msg.sender];
        if (p.challenge == bytes32(0)) revert NoPendingBinding();
        if (block.timestamp >= bindDeadline || finalized) revert BindingClosed();
        if (p.lastSubmitTs != 0 && block.timestamp < uint256(p.lastSubmitTs) + VERIFY_COOLDOWN) revert Cooldown();
        p.lastSubmitTs = uint64(block.timestamp);
        ICampaignFactory(factory).emitVerifyRequest(msg.sender, p.videoId, p.challenge);
    }

    /// @return reason Zero on success; otherwise a stable ASCII bytes32 reason code.
    function applyBind(address wallet, bytes32 videoId, bytes32 challenge, uint64 baselineViews)
        external onlyReceiver nonReentrant returns (bytes32 reason)
    {
        if (finalized || block.timestamp >= bindDeadline) return ReportReasons.DEADLINE;
        PendingBind storage p = pendingBinding[wallet];
        if (challenge == bytes32(0) || p.challenge != challenge || p.videoId != videoId) return ReportReasons.NO_MATCH;
        if (videoOwner[videoId] != address(0)) return ReportReasons.VIDEO_TAKEN;
        Creator storage c = _creator[wallet];
        if (c.videoCount >= maxVideosPerCreator) return ReportReasons.MAX_VIDEOS;
        if (!c.bound) {
            if (creatorCount >= maxCreators) return ReportReasons.FULL;
            if (liability + capPerCreator > usdc.balanceOf(address(this))) return ReportReasons.BUDGET;
            c.bound = true;
            c.boundAt = uint64(block.timestamp);
            c.remaining = uint128(capPerCreator);
            c.upfront = uint128(capPerCreator * upfrontPpm / PPM);
            liability += capPerCreator;
            ++creatorCount;
            creatorList.push(wallet);
        }
        videoOwner[videoId] = wallet;
        c.videoIds[c.videoCount] = videoId;
        ++c.videoCount;
        VideoState storage v = _video[videoId];
        v.creator = wallet;
        v.baseline = baselineViews;
        v.lastUpdateTs = uint64(block.timestamp);
        uint32 epoch = uint32(block.timestamp / bucketLen);
        uint256 index = epoch % BUCKETS;
        v.bucketEpoch[index] = epoch;
        v.bucketMin[index] = baselineViews;
        // Clear the pending request but keep the nonce counter so a past challenge can never be reissued.
        uint32 nextNonce = p.nonce;
        delete pendingBinding[wallet];
        pendingBinding[wallet].nonce = nextNonce;
        emit Bound(wallet, videoId, baselineViews, c.boundAt);
        // Instant settlement: the upfront share is paid in this same transaction, on the creator's first video only.
        // If the transfer fails the state is restored and the amount stays claimable through `claim`.
        if (c.upfront != 0 && c.videoCount == 1) _pay(wallet, false);
        return bytes32(0);
    }

    function applySnapshot(bytes32[] calldata ids, uint64[] calldata views_, uint64 ts)
        external onlyReceiver nonReentrant returns (bytes32)
    {
        if (finalized) return ReportReasons.FINALIZED;
        return _applyObservations(ids, views_, ts, false);
    }

    function applyFinal(bytes32[] calldata ids, uint64[] calldata views_, uint64 ts)
        external onlyReceiver nonReentrant returns (bytes32)
    {
        if (finalized) return ReportReasons.FINALIZED;
        if (block.timestamp < uint256(bindDeadline) + scheduleLength) return ReportReasons.FINAL_TOO_EARLY;
        bytes32 reason = _applyObservations(ids, views_, ts, true);
        if (reason != bytes32(0)) return reason;
        _finalize(false);
        return bytes32(0);
    }

    function applyPayout(address[] calldata wallets) external onlyReceiver nonReentrant returns (bytes32) {
        if (wallets.length > MAX_BATCH) return ReportReasons.BATCH_TOO_LARGE;
        for (uint256 i; i < MAX_BATCH; ++i) {
            if (i == wallets.length) break;
            _pay(wallets[i], true);
        }
        return bytes32(0);
    }

    function claim(address wallet) external nonReentrant {
        _pay(wallet, false);
    }

    function finalizeFromLastSnapshot() external nonReentrant {
        if (finalized) revert CampaignFinalized();
        if (block.timestamp < uint256(bindDeadline) + scheduleLength + deadmanTimeout) revert TooEarly();
        _finalize(true);
    }

    function settle(address wallet) external nonReentrant {
        if (!finalized) revert NotFinalized();
        Creator storage c = _creator[wallet];
        if (!c.bound) revert NotBound();
        if (!c.settled) {
            // The upfront share is part of the final entitlement, so an unpaid upfront (blocked transfer) is not lost.
            uint256 earned = _earned(c);
            if (c.upfront > earned) earned = c.upfront;
            uint256 remaining = earned > c.paid ? earned - c.paid : 0;
            liability -= c.remaining - remaining;
            c.remaining = uint128(remaining);
            c.settled = true;
            ++settledCount;
            emit Settled(wallet, earned, remaining);
        }
        _pay(wallet, false);
    }

    function sweep() external nonReentrant {
        if (block.timestamp < bindDeadline) revert TooEarly();
        uint256 amount = usdc.balanceOf(address(this)) - liability;
        if (amount != 0) {
            if (_transfer(brand, amount)) emit Swept(brand, amount);
            else emit PayoutFailed(brand, amount);
        }
    }

    function claimable(address wallet) public view returns (uint256) {
        Creator storage c = _creator[wallet];
        if (!c.bound) return 0;
        // The upfront share is always entitled; view-based entitlement only counts while snapshots are fresh.
        uint256 entitled = c.upfront;
        if (finalized || block.timestamp <= uint256(lastSnapshotTs) + staleAfter) {
            uint256 fraction = finalized ? PPM : ScheduleLib.fractionPpm(_schedule, block.timestamp - c.boundAt);
            uint256 viewBased = _earned(c) * fraction / PPM;
            if (viewBased > entitled) entitled = viewBased;
        }
        if (entitled <= c.paid) return 0;
        uint256 amount = entitled - c.paid;
        return amount > c.remaining ? c.remaining : amount;
    }

    function creators(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        if (limit > MAX_PAGE || offset > creatorList.length) revert InvalidPage();
        uint256 count = creatorList.length - offset;
        if (count > limit) count = limit;
        page = new address[](count);
        for (uint256 i; i < MAX_PAGE; ++i) {
            if (i == count) break;
            page[i] = creatorList[offset + i];
        }
    }

    function creatorInfo(address wallet) external view returns (Creator memory) { return _creator[wallet]; }
    function videosOf(address wallet) external view returns (bytes32[] memory ids) {
        Creator storage c = _creator[wallet];
        ids = new bytes32[](c.videoCount);
        for (uint256 i; i < MAX_VIDEOS; ++i) {
            if (i == c.videoCount) break;
            ids[i] = c.videoIds[i];
        }
    }
    function videoInfo(bytes32 id) external view returns (VideoState memory) { return _video[id]; }
    function schedule() external view returns (ScheduleLib.Segment[] memory) { return _schedule; }

    function _applyObservations(bytes32[] calldata ids, uint64[] calldata views_, uint64 ts, bool isFinal)
        private returns (bytes32)
    {
        if (ids.length != views_.length) return ReportReasons.LENGTH_MISMATCH;
        if (ids.length > MAX_SNAPSHOT_ENTRIES) return ReportReasons.BATCH_TOO_LARGE;
        for (uint256 i; i < MAX_SNAPSHOT_ENTRIES; ++i) {
            if (i == ids.length) break;
            address wallet = videoOwner[ids[i]];
            if (wallet == address(0)) {
                emit EntrySkipped(ids[i], ReportReasons.UNKNOWN_VIDEO);
                continue;
            }
            VideoState storage v = _video[ids[i]];
            if (ts < v.lastUpdateTs) {
                emit EntrySkipped(ids[i], ReportReasons.STALE_TS);
                continue;
            }
            _observe(_creator[wallet], v, views_[i], ts);
        }
        if (ts > lastSnapshotTs) lastSnapshotTs = ts;
        emit SnapshotApplied(ts, ids.length, isFinal);
        return bytes32(0);
    }

    function _observe(Creator storage c, VideoState storage v, uint64 views_, uint64 ts) private {
        uint32 epoch = uint32(ts / bucketLen);
        uint256 index = epoch % BUCKETS;
        if (v.bucketEpoch[index] != epoch) {
            v.bucketEpoch[index] = epoch;
            v.bucketMin[index] = views_;
        } else if (views_ < v.bucketMin[index]) {
            v.bucketMin[index] = views_;
        }
        uint64 candidate = type(uint64).max;
        bool found;
        for (uint256 i; i < BUCKETS; ++i) {
            uint32 e = v.bucketEpoch[i];
            if (e != 0 && uint256(e) + BUCKETS > epoch) {
                found = true;
                if (v.bucketMin[i] < candidate) candidate = v.bucketMin[i];
            }
        }
        if (!found) return;
        uint256 net = candidate > v.baseline ? candidate - v.baseline : 0;
        uint256 dt = ts - v.lastUpdateTs;
        if (dt > MAX_ALLOWANCE_WINDOW) dt = MAX_ALLOWANCE_WINDOW;
        uint256 maximum = uint256(v.credited) + uint256(maxGrowthPerDay) * dt / 1 days;
        uint256 credited = net <= v.credited ? net : (net < maximum ? net : maximum);
        c.creditedViews = uint128(uint256(c.creditedViews) + credited - v.credited);
        v.credited = uint64(credited);
        v.lastUpdateTs = ts;
    }

    function _earned(Creator storage c) private view returns (uint256) {
        uint256 earned = uint256(c.creditedViews) * ratePerThousand / 1000;
        return earned > capPerCreator ? capPerCreator : earned;
    }

    function _pay(address wallet, bool withFloor) private {
        uint256 amount = claimable(wallet);
        if (amount == 0 || (withFloor && amount < minPayout)) return;
        Creator storage c = _creator[wallet];
        c.paid += uint128(amount);
        c.remaining -= uint128(amount);
        liability -= amount;
        totalPaid += amount;
        if (!_transfer(wallet, amount)) {
            c.paid -= uint128(amount);
            c.remaining += uint128(amount);
            liability += amount;
            totalPaid -= amount;
            emit PayoutFailed(wallet, amount);
        } else {
            emit Paid(wallet, amount);
        }
    }

    function _transfer(address to, uint256 amount) private returns (bool) {
        (bool success, bytes memory result) = address(usdc).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return success && (result.length == 0 || (result.length >= 32 && _returnedTrue(result)));
    }

    function _returnedTrue(bytes memory result) private pure returns (bool) {
        // Reject noncanonical bools without letting abi.decode abort a payout batch.
        if (abi.decode(result, (uint256)) > 1) return false;
        return abi.decode(result, (bool));
    }

    function _finalize(bool deadman) private {
        finalized = true;
        finalizedAt = uint64(block.timestamp);
        emit Finalized(finalizedAt, deadman);
    }

    function _validVideoId(bytes32 id) private pure returns (bool) {
        for (uint256 i; i < 32; ++i) {
            uint8 ch = uint8(id[i]);
            if (i >= 11) {
                if (ch != 0) return false;
            } else if (!((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
                || (ch >= 48 && ch <= 57) || ch == 95 || ch == 45)) return false;
        }
        return true;
    }
}
