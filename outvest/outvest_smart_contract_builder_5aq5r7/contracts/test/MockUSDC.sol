// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TEST ONLY. 6-decimal USDC mock with a recipient blocklist (revert or `false` mode),
///         an optional transfer fee (for UnsupportedToken tests) and per-sender recipient tracking.
contract MockUSDC is ERC20 {
    mapping(address => bool) public blocked;
    bool public returnFalseOnBlocked;
    uint256 public feeBps;
    mapping(address => mapping(address => uint256)) public sentTo;
    mapping(address => address[]) private _recipients;

    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address who, bool isBlocked) external {
        blocked[who] = isBlocked;
    }

    function setReturnFalse(bool v) external {
        returnFalseOnBlocked = v;
    }

    function setFeeBps(uint256 bps) external {
        feeBps = bps;
    }

    function recipientsOf(address from) external view returns (address[] memory) {
        return _recipients[from];
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (returnFalseOnBlocked && blocked[to]) return false;
        return super.transfer(to, value);
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to], "blocked");
        if (from != address(0) && to != address(0)) {
            if (feeBps != 0) {
                uint256 fee = value * feeBps / 10_000;
                if (fee != 0) {
                    super._update(from, address(0), fee);
                    value -= fee;
                }
            }
            if (sentTo[from][to] == 0) _recipients[from].push(to);
            sentTo[from][to] += value;
        }
        super._update(from, to, value);
    }
}
