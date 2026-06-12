// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";

/// @dev Zero-interest IRM by default; `setRate` lets a test charge a non-zero
///      per-second borrow rate so the expectedDebt accrual path is exercised.
contract MockIrm {
    /// @dev WAD-scaled borrow rate per second; 0 means no accrual.
    uint256 public rate;

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function borrowRate(MarketParams memory, Market memory) external view returns (uint256) {
        return rate;
    }

    function borrowRateView(MarketParams memory, Market memory) external view returns (uint256) {
        return rate;
    }
}
