// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FCMVault, MORPHO} from "../src/FCMVault.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorpho} from "./mocks/MockMorpho.sol";
import {MockUniswapV3Pool} from "./mocks/MockUniswapV3Pool.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockIrm} from "./mocks/MockIrm.sol";

abstract contract StalePriceArbBase is Test {
    IERC20 constant WETH = IERC20(0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);
    IERC20 constant PYUSD0 = IERC20(0x99aF3EeA856556646C98c8B9b2548Fe815240750);
    IERC20 constant FUSDEV = IERC20(0xd069d989e2F44B70c65347d1853C0c67e10a9F8D);
    address constant MOCK_IRM = 0xdFC4f7951EcDd2D505b6406e9c886c0dB9393546;

    uint256 internal constant WETH_PRICE = 2000e36;
    uint256 internal constant YIELD_PRICE = 1e36;
    uint256 internal constant LLTV = 0.86e18;
    uint256 internal constant HF_MIN = 1.25e18;
    uint256 internal constant HF_MAX = 1.65e18;
    uint256 internal constant HF_MIN_TARGET = 1.3e18;
    uint256 internal constant HF_MAX_TARGET = 1.6e18;
    uint256 internal constant YIELD_FACTOR_MAX = 1.01e18;
    uint24 internal constant FEE = 100;
    uint24 internal constant FEE_ASSET_DEBT = 3000;

    FCMVault internal vault;
    MockOracle internal marketOracle;
    MockOracle internal yieldOracle;
    MockUniswapV3Pool internal yieldPool; // the yield/debt pool the vault reads slot0 from for swap limits

    address internal admin = address(0x12345);
    address internal honest = address(0xA11CE);
    address internal attacker = address(0xBAD);

    /// @dev Etch the shared token/Morpho/IRM mocks. The SWAP_ROUTER is etched per-suite
    ///      (static MockSwapRouter vs stateful MockStatefulCpmmRouter) by the subclass.
    function _etchCommon() internal {
        bytes memory erc20Code = address(new MockERC20()).code;
        vm.etch(address(WETH), erc20Code);
        vm.etch(address(PYUSD0), erc20Code);
        vm.etch(address(FUSDEV), erc20Code);
        vm.etch(address(MORPHO), address(new MockMorpho()).code);
        vm.etch(MOCK_IRM, address(new MockIrm()).code);
    }

    /// @dev Construct the oracles and the vault; set maxTvl and grant early-access roles.
    function _deployVault(uint256 maxTvl) internal {
        marketOracle = new MockOracle(WETH_PRICE);
        yieldOracle = new MockOracle(YIELD_PRICE);
        yieldPool = new MockUniswapV3Pool();
        vault = new FCMVault(
            FCMVault.InitParams({
                collateral: WETH,
                loanToken: PYUSD0,
                yieldToken: FUSDEV,
                marketOracle: address(marketOracle),
                marketIrm: MOCK_IRM,
                marketLltv: LLTV,
                feeYieldDebt: FEE,
                feeAssetDebt: FEE_ASSET_DEBT,
                yieldDebtPool: address(yieldPool),
                assetDebtPool: address(new MockUniswapV3Pool()),
                healthFactorMin: HF_MIN,
                healthFactorMax: HF_MAX,
                healthFactorMinTarget: HF_MIN_TARGET,
                healthFactorMaxTarget: HF_MAX_TARGET,
                yieldFactorMax: YIELD_FACTOR_MAX,
                yieldOracle: address(yieldOracle),
                admin: admin,
                recoveryDelay: 7 days,
                name: "Flow Credit Markets WETH",
                symbol: "fcmWETH"
            })
        );
        vm.startPrank(admin);
        vault.setMaxTvl(maxTvl);
        vault.grantRole(vault.EARLY_ACCESS_ROLE(), honest);
        vault.grantRole(vault.EARLY_ACCESS_ROLE(), attacker);
        vm.stopPrank();
    }

    function _deposit(address who, uint256 amount) internal returns (uint256 shares) {
        MockERC20(address(WETH)).mint(who, amount);
        vm.startPrank(who);
        WETH.approve(address(vault), amount);
        shares = vault.deposit(amount, who);
        vm.stopPrank();
    }
}
