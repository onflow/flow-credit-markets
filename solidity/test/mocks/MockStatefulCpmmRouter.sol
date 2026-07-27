// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev STATEFUL constant-product (x*y=k) router: unlike MockCpmmSwapRouter, reserves ARE
///      updated after each swap, so sequential trades move the spot price — required to model
///      an attacker *manufacturing* a DEX divergence and paying the round-trip price impact.
///      Per-pair reserves (a token can appear in multiple pools). No fees (conservative:
///      omitting them makes an attack strictly easier). Ignores sqrtPriceLimitX96 — these
///      tests never set one (only rebalance uses a price limit, which they don't exercise).
contract MockStatefulCpmmRouter {
    struct Pool {
        uint256 r0; // r0 = lower-addressed token
        uint256 r1;
    }

    mapping(bytes32 => Pool) internal pools;

    function _key(address a, address b) internal pure returns (bytes32) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(t0, t1));
    }

    /// @notice Seed a pool. `rA`/`rB` are reserves for `tokenA`/`tokenB` respectively.
    function setPool(address tokenA, uint256 rA, address tokenB, uint256 rB) external {
        bytes32 k = _key(tokenA, tokenB);
        if (tokenA < tokenB) pools[k] = Pool(rA, rB);
        else pools[k] = Pool(rB, rA);
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        require(p.amountOutMinimum == 0, "amountOutMinimum unsupported");
        Pool storage pool = pools[_key(p.tokenIn, p.tokenOut)];
        bool inIs0 = p.tokenIn < p.tokenOut;
        uint256 rIn = inIs0 ? pool.r0 : pool.r1;
        uint256 rOut = inIs0 ? pool.r1 : pool.r0;
        require(rIn > 0 && rOut > 0, "reserves unset");

        amountOut = rOut - Math.mulDiv(rIn, rOut, rIn + p.amountIn);
        if (inIs0) {
            pool.r0 = rIn + p.amountIn;
            pool.r1 = rOut - amountOut;
        } else {
            pool.r1 = rIn + p.amountIn;
            pool.r0 = rOut - amountOut;
        }

        MockERC20(p.tokenIn).burn(msg.sender, p.amountIn);
        MockERC20(p.tokenOut).mint(p.recipient, amountOut);
    }

    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata p)
        external
        payable
        returns (uint256 amountIn)
    {
        Pool storage pool = pools[_key(p.tokenIn, p.tokenOut)];
        bool inIs0 = p.tokenIn < p.tokenOut;
        uint256 rIn = inIs0 ? pool.r0 : pool.r1;
        uint256 rOut = inIs0 ? pool.r1 : pool.r0;
        require(rIn > 0 && rOut > 0 && p.amountOut < rOut, "reserves unset/insufficient");

        // amountIn = rIn*out/(rOut-out), round up
        amountIn = Math.mulDiv(rIn, p.amountOut, rOut - p.amountOut, Math.Rounding.Ceil);
        require(amountIn <= p.amountInMaximum, "Too much requested");

        if (inIs0) {
            pool.r0 = rIn + amountIn;
            pool.r1 = rOut - p.amountOut;
        } else {
            pool.r1 = rIn + amountIn;
            pool.r0 = rOut - p.amountOut;
        }

        MockERC20(p.tokenIn).burn(msg.sender, amountIn);
        MockERC20(p.tokenOut).mint(p.recipient, p.amountOut);
    }
}
