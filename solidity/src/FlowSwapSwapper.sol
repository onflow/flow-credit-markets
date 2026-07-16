// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapper} from "./interfaces/ISwapper.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

/// @title FlowSwapSwapper
/// @notice Thin ISwapper implementation that routes all swaps through
///         FlowSwap V3's SwapRouter02. Tokens are received from the caller
///         (pushed before the call), swapped, and the output plus any unspent
///         input is returned to `msg.sender`. The caller is responsible for
///         verifying the amounts it receives — this contract is a dumb pipe.
contract FlowSwapSwapper is ISwapper {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /// @inheritdoc ISwapper
    function swapExactIn(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    /// @inheritdoc ISwapper
    function swapExactInToLimit(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        // Return any unspent tokenIn (partial fill: the router consumed less
        // than amountIn and left the remainder with this contract).
        uint256 unspent = IERC20(tokenIn).balanceOf(address(this));
        if (unspent > 0) IERC20(tokenIn).safeTransfer(msg.sender, unspent);
    }

    /// @inheritdoc ISwapper
    function swapExactOut(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut, uint256 maxAmountIn)
        external
        returns (uint256 amountIn)
    {
        IERC20(tokenIn).forceApprove(address(swapRouter), maxAmountIn);
        amountIn = swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountOut: amountOut,
                amountInMaximum: maxAmountIn,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        // Return unspent tokenIn.
        uint256 unspent = IERC20(tokenIn).balanceOf(address(this));
        if (unspent > 0) IERC20(tokenIn).safeTransfer(msg.sender, unspent);
    }
}
