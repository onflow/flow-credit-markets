// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ISwapRouter02} from "../../src/interfaces/external/ISwapRouter02.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Rate-based swap mock. Each ordered token pair carries a WAD-scaled rate
///      (units of tokenOut per tokenIn); unset pairs default to 1:1, so with no
///      rates set this is a lossless flat router. `feeBps` (basis points) is taken
///      off the output; a per-fee-tier override (`setFeeBpsForPool`) haircuts one
///      pool without touching the others. Setting per-pair rates pins the DEX
///      execution price independently of the vault's (possibly stale) oracle — the
///      exact discrepancy an oracle front-run exploits. Ignores the price-limit
///      field. Reverts on a zero input amount, like UniswapV3Pool's
///      `require(amountSpecified != 0, 'AS')`.
contract MockSwapRouter {
    uint256 internal constant WAD = 1e18;

    uint256 public feeBps;

    mapping(uint24 => uint256) internal poolFeeBps;
    mapping(uint24 => bool) internal poolFeeSet;
    mapping(address => mapping(address => uint256)) public rate;

    function setFeeBps(uint256 newFeeBps) external {
        require(newFeeBps <= 10_000, "fee > 100%");
        feeBps = newFeeBps;
    }

    /// @dev Override the fee for a single pool (by fee tier); overrides the
    ///      global `feeBps` for swaps routed through that tier only.
    function setFeeBpsForPool(uint24 fee, uint256 newFeeBps) external {
        require(newFeeBps <= 10_000, "fee > 100%");
        poolFeeBps[fee] = newFeeBps;
        poolFeeSet[fee] = true;
    }

    /// @dev WAD-scaled units of tokenOut per tokenIn; unset defaults to 1:1.
    function setRate(address tokenIn, address tokenOut, uint256 rateWad) external {
        rate[tokenIn][tokenOut] = rateWad;
    }

    function _rate(address tokenIn, address tokenOut) internal view returns (uint256 r) {
        r = rate[tokenIn][tokenOut];
        if (r == 0) r = WAD;
    }

    function exactInputSingle(ISwapRouter02.ExactInputSingleParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        require(p.amountIn != 0, "AS");
        uint256 bps = poolFeeSet[p.fee] ? poolFeeBps[p.fee] : feeBps;
        MockERC20(p.tokenIn).burn(msg.sender, p.amountIn);
        amountOut = p.amountIn * _rate(p.tokenIn, p.tokenOut) / WAD * (10_000 - bps) / 10_000;
        require(amountOut >= p.amountOutMinimum, "Too little received");
        MockERC20(p.tokenOut).mint(p.recipient, amountOut);
    }

    /// @dev Exact-output mirror of `exactInputSingle`: grosses the input up by the
    ///      fee and inverts the rate to deliver exactly `amountOut`, reverting if it
    ///      exceeds `amountInMaximum`. Ignores fee tier and price-limit fields.
    function exactOutputSingle(ISwapRouter02.ExactOutputSingleParams calldata p)
        external
        payable
        returns (uint256 amountIn)
    {
        uint256 denom = 10_000 - feeBps;
        uint256 grossOut = (p.amountOut * 10_000 + denom - 1) / denom;
        uint256 r = _rate(p.tokenIn, p.tokenOut);
        amountIn = (grossOut * WAD + r - 1) / r;
        require(amountIn <= p.amountInMaximum, "Too much requested");
        MockERC20(p.tokenIn).burn(msg.sender, amountIn);
        MockERC20(p.tokenOut).mint(p.recipient, p.amountOut);
    }
}
