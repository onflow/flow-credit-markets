// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @dev Morpho IOracle-compatible mock: returns a fixed 1e36-scaled price.
///      `setReverts(true)` makes `price()` revert, like a Pyth adapter past
///      its staleness bound.
contract MockOracle {
    uint256 public priceValue;
    bool public reverts;

    constructor(uint256 priceValue_) {
        priceValue = priceValue_;
    }

    function price() external view returns (uint256) {
        require(!reverts, "StalePrice");
        return priceValue;
    }

    function setPrice(uint256 newPrice) external {
        priceValue = newPrice;
    }

    function setReverts(bool reverts_) external {
        reverts = reverts_;
    }
}
