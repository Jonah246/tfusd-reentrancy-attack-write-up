# true-fi-pool-reentrancy-attack

[true-fi-strategy](https://etherscan.io/address/0xe7f52d4F1C056FbfBF2b377de760510fa088bAef).
[CurveYearnStrategy](https://github.com/trusttoken/smart-contracts/blob/main/contracts/truefi2/strategies/CurveYearnStrategy.sol)
Three true-fi pools (TfUSDC, TfTUSD, TfUSDT) use the same strategy implementation. Approximately 500K worth of CRV token were at risks at the time the issue was reported.

## Summary
There's a permissionless function [sellCrv](https://github.com/trusttoken/smart-contracts/blob/76854d53c5036777286d4392495ef28cd5c5173a/contracts/truefi2/strategies/CurveYearnStrategy.sol#L228-L245) in `CurveYearnStrategy`. The `sellCrv` sells crv token into stableCoins (USDC/ USDC/ TUSD) and send it into the trueFi pool.

```solidity
   /**
     * @dev Swap collected CRV on 1inch and transfer gains to the pool
     * Receiver of the tokens should be the pool
     * Revert if resulting exchange price is much smaller than the oracle price
     * @param data Data that is forwarded into the 1inch exchange contract. Can be acquired from 1Inch API https://api.1inch.exchange/v3.0/1/swap
     * [See more](https://docs.1inch.exchange/api/quote-swap#swap)
     */
    function sellCrv(bytes calldata data) external {
        (I1Inch3.SwapDescription memory swap, uint256 balanceDiff) = _1Inch.exchange(data);

        uint256 expectedGain = normalizeDecimals(crvOracle.crvToUsd(swap.amount));

        require(swap.srcToken == address(minter.token()), "CurveYearnStrategy: Source token is not CRV");
        require(swap.dstToken == address(token), "CurveYearnStrategy: Destination token is not TUSD");
        require(swap.dstReceiver == pool, "CurveYearnStrategy: Receiver is not pool");

        require(balanceDiff >= conservativePriceEstimation(expectedGain), "CurveYearnStrategy: Not optimal exchange");
    }
```

There are four assertions:
1. `dstReceiver` needs to be the pool.
2. `dstToken` needs to be the pool's token. Attackrs can not sell the CRV into strange tokens.
3. `srcToken` needs to be CRV. Attackers can not sell other tokens.
4. `balanceDiff >= conservativePriceEstimation(expectedGain)`.  Attackers can not sell CRV at a bad price. 


However, the contract considers it's a good trade as long as `balanceDiff` is large enough. `balanceDiff` is calculated in the OneInch library
[OneInchExchange.sol#L59-L72](https://github.com/trusttoken/smart-contracts/blob/76854d53c5036777286d4392495ef28cd5c5173a/contracts/truefi2/libraries/OneInchExchange.sol#L59-L72). It compares `balanceOf(receiver)` before and after the swap. As long as the pool's balance increases during the swap, it's a good trade. **If the attacker joins the pool during the swap, the pool's balance increases and he can take free tfUSDC away** It turns out `oneInch` allows anyone to do their own swap. The attacker can pull the crv, do the swap and join the pool. The attacker ends up with free tfUSDC.

## Exploit steps
* Triggers collectCrv
* Call `sellCrv` and set the `srcReceiver` to the exploit contract.
  * Sells `CRV` in the callBack function.
  * Join the trueFi pool.
* Enjoy the free tfUSDC.

## Reproduce
1. `npm i`
2. `npx hardhat test test/reentrancy.js`

Here's setting of hardhat
```js
{
  solidity: "0.6.12",
  networks: {
  hardhat: {
    forking: {
      url: "https://eth-mainnet.alchemyapi.io/v2/{}",
      blockNumber: 13760924
    }
  },
  }, 
  mocha: {
    timeout: 1200000,
  }
}
```
## Mitigation
Using oneInch in the strategy is clever. As the market fluctuates all the time, 
fixing one swapping route would lead to bad trades. (Check out how akward it is to do it without oneInch [sellCrv](git@github.com:Jonah246/true-fi-reentrancy-writeup.git)) However, strange things would happen when the receiver is a Vault.

Setting `sellCrv` a public function doesn't bring much benefit.



