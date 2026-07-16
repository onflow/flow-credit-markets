// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ISwapper
/// @notice Minimal swap interface for the vault's three swap patterns.
///         Implementations route trades to an on-chain AMM (e.g. FlowSwap V3)
///         and return output + unspent input to the caller. The vault measures
///         its own balance deltas after each call — that's the trust boundary:
///         the swapper is not trusted to self-report, only to deliver tokens.
interface ISwapper {
    /// @notice Swap exactly `amountIn` of `tokenIn` for as much `tokenOut` as
    ///         the pool will give. Caller must have transferred `amountIn` of
    ///         `tokenIn` to this contract before calling.
    /// @dev    No price bound — the pool decides the realized rate. Returns
    ///         `amountOut` of `tokenOut` to `msg.sender`.
    function swapExactIn(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn)
        external
        returns (uint256 amountOut);

    /// @notice Swap up to `amountIn` of `tokenIn` for `tokenOut`, stopping
    ///         early if the pool's marginal price reaches `sqrtPriceLimitX96`.
    ///         Caller must have transferred `amountIn` of `tokenIn` to this
    ///         contract before calling.
    /// @dev    On a partial fill the pool consumes LESS than `amountIn`; the
    ///         unspent `tokenIn` and the realized `amountOut` of `tokenOut` are
    ///         both returned to `msg.sender`. A zero `sqrtPriceLimitX96` means
    ///         no limit (same as `swapExactIn`).
    function swapExactInToLimit(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    /// @notice Swap `tokenIn` for exactly `amountOut` of `tokenOut`, spending
    ///         at most `maxAmountIn`. Caller must have transferred `maxAmountIn`
    ///         of `tokenIn` to this contract before calling.
    /// @dev    Returns `amountOut` of `tokenOut` and any unspent `tokenIn` to
    ///         `msg.sender`. Reverts in the underlying router if the required
    ///         input would exceed `maxAmountIn`.
    function swapExactOut(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut, uint256 maxAmountIn)
        external
        returns (uint256 amountIn);
}
