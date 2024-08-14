# Mission #1 - Perpetuals

# Motivation

A key separator between a junior Web3 developer/security researcher and a senior one is often deep understanding of DeFi concepts and archetypes. Perpetuals are one such DeFi archetype of which a deep understanding will serve you well.

Throughout our 4 weeks you will embark on 4 missions with your partner, each will deepen your understanding and mastery of decentralized perpetual futures.

With the first mission, you and your partner will research and understand what a perpetual futures protocol is, what it achieves, and how it works. And then, you’ll build one.

The concept of perpetual futures is introduced in the sections below.

# Goal & Deliverables

The first mission focuses on implementing roughly 50% of the basic functionality of a decentralized perpetuals protocol.

Do not fret! Perpetual protocols do not have to be by any means as large as the 10,000+ SLOC [GMX V2 codebase](https://github.com/gmx-io/gmx-synthetics), in fact, if you find yourself with more than a couple hundred lines for this first mission you may be headed in the wrong direction.

- A protocol name
- Smart Contract(s) with the following functionalities, with corresponding tests:
    - Liquidity Providers can deposit and withdraw liquidity.
    - A way to get the realtime price of the asset being traded.
    - Traders can open a perpetual position for BTC, with a given size and collateral.
    - Traders can increase the size of a perpetual position.
    - Traders can increase the collateral of a perpetual position.
    - Traders cannot utilize more than a configured percentage of the deposited liquidity.
    - Liquidity providers cannot withdraw liquidity that is reserved for positions.
- README
    - How does the system work? How would a user interact with it?
    - What actors are involved? Is there a keeper? What is the admin tasked with?
    - What are the known risks/issues?
    - Any pertinent formulas used.

# Details

### What are perpetuals?

Perpetuals are essentially just a way for a trader to bet on the price of a certain *index token* without actually buying the token while enabling the trader to employ *leverage*.

**Why perpetual?**

Perpetuals are named as such because a trader can keep their “perpetual” *position* open for as long as they’d like, or in perpetuity.

**So what’s a position?**

The entire protocol revolves around “positions” that belong to traders, a position is made up of the following:

- Size - This is how much “virtual” capital a trader is commanding, the size of a BTC perpetual position might be 1.5 BTC. If the price of BTC goes up, the trader is able to realize the profits earned on the 1.5 BTC in their position.
- Collateral - An amount of assets used to “back” a trader’s position, when trader’s lose money, their losses come out of the collateral. If the amount of collateral is deemed insufficient for the size of a position, the position is *liquidated* or force closed.

The `size / collateral` is the *leverage* of a position. E.g. if I open a position with $10,000 of USDC as collateral and a size of $20,000 of BTC, my leverage is 2x.

**Long/Short**

There are two different *directions* a perpetual position can take.

- Long → The trader profits when the price of the *index token* goes up, and loses when the price of the *index token* go down.
- Short → The trader profits when the price of the *index token* goes down, and loses when the price of the *index token* goes up.

Let’s have a look at an example of a *long* position where ETH is our *index token*:

- The current price of ETH is $5,000.
- The maximum leverage allowed before liquidation is 15x
- Bob opens a *long* position with $1,000 of USDC as collateral and $10,000 of size. At the current price of ETH his $10,000 of size translates to 2 ETH of size in tokens for the position.
- Bob has $10,000 of size and only $1,000 of collateral — therefore the leverage of Bob’s position is 10x, which is within the permissible range.
- The price of ETH moves up to $6,000 — a 20% gain.
- Bob is now in profit! His perpetual position has 2 ETH of size in tokens and his cost basis was $5,000 — so his net PnL (profit and loss) is `($6,000 - $5,000) * 2 = $2,000` or `(Current Market Value - Average Position Price) * Size In Tokens`.
- Bob may close his position and realize this $2,000 in profits, however Bob is greedy and he keeps his position open in hopes of more profit.
- Inevitably, the price of ETH falls to $4,750.
- Bob’s profits have evaporated, in fact he is now in a loss! His perpetual position now has the following PnL: `($4,750 - $5,000) * 2 = -$500`.
- This $500 loss is to be covered by Bob’s collateral, meaning his remaining collateral is: `$1,000 - $500 = $500`. Bob now has just $500 of remaining collateral left to “back” his position, therefore his leverage is his $10,000 of original size divided by his $500 of remaining collateral, `$10,000 / $500 = 20x`.
- Bob’s position has surpassed the liquidation threshold and is therefore *liquidated.* His collateral is seized, his $500 of losses are sent to the liquidity providers along with an additional liquidation fee, his remaining collateral is sent back to him.

<aside>
💡 For Mission #1 you are not tasked with implementing decreasing, closing, or liquidating positions — but it will be helpful to ponder what this might look like.

</aside>

And now let’s see how a *short* position behaves:

- The current price of ETH is $5,000.
- The maximum leverage allowed before liquidation is 15x.
- Bob opens a *short* position with $1,000 of USDC as collateral and $10,000 of size. At the current price of ETH his $10,000 of size translates to 2 ETH of size in tokens for the position.
- Bob’s leverage is 10x.
- The price of ETH moves down to $4,000 — a 20% decrease.
- Bob is now in profit! His perpetual position has 2 ETH of size in tokens and his cost basis was $5,000 — so his net PnL is `($5,000 - $4,000) * 2 = $2,000` or `(Average Position Price - Current Market Value) * Size In Tokens`.
- Bob may close his position and realize this $2,000 in profits, however Bob is greedy and he keeps his position open in hopes of more profit.
- Inevitably, the price of ETH rises to $5,250.
- Bob’s profits have evaporated, in fact he is now in a loss! His perpetual position now has the following PnL: `($5,000 - $5,250) * 2 = -$500`.
- This $500 loss is to be covered by Bob’s collateral, meaning his remaining collateral is: `$1,000 - $500 = $500`. Bob now has just $500 of remaining collateral left to “back” his position, therefore his leverage is his $10,000 of original size divided by his $500 of remaining collateral, `$10,000 / $500 = 20x`.
- Bob’s position has surpassed the liquidation threshold and is therefore *liquidated.* His collateral is seized, his $500 of losses are sent to the liquidity providers along with an additional liquidation fee, his remaining collateral is sent back to him.

<aside>
💡 Notice that the formula for PnL of a position for a long is different than for a short:

```
Long PnL = (Current Market Value - Average Position Price) * Size In Tokens
Short PnL = (Average Position Price - Current Market Value) * Size In Tokens
```

</aside>

### Traders

Traders are the actors opening perpetual positions and betting on the price of the *index token*.

Traders profit when the price of the *index token* moves in the direction they predict, and lose when it moves in the direction opposite to what they predict.

Traders must provide collateral for their *position,* the collateral is used to cover their losses in the event that price moves in the opposite direction of what they predicted.

### Liquidity Providers

Liquidity providers take the opposite side of traders, they stand to profit when traders lose money or are liquidated. Liquidity providers also often collect fees from the trader, such as opening and closing fees, or borrowing fees.

Liquidity providers provide the assets that are used to pay out profit for traders. When a trader profits they get tokens from the liquidity providers. When a trader loses, they pay tokens to the liquidity providers out of their position’s collateral.

<aside>
💡 For Mission #1 you are not tasked with implementing any fees or handling the settling of profits or losses — but it will be helpful to ponder what this might look like.

</aside>

### Open Interest

Open interest is the measure of the aggregate size of all open positions.

For your implementation you might consider tracking two types of open interest:

- Open Interest — Measured in a USD value, incremented by the “size” that a position is initially opened and increased with.
- Open Interest In Tokens — Measured in a *index token* value, incremented by the “size in tokens” that a position is opened with and increased with.

### Liquidity Reserves

Liquidity reserves are necessary such that at all times there are enough assets in the liquidity pool (provided by liquidity providers) to pay out the profits for positions. 

If there is only 10 USDC of liquidity deposited by liquidity providers, then allowing a trader to open a perpetual contract with $10,000 of size would be irresponsible. If the price moves even a little bit in the trader’s direction they will be more than $10 in profit, yet there will not be enough USDC to pay them out.

Liquidity reserve restrictions may be somewhat arbitrary, similarly to the configured liquidation threshold. Here’s a reasonable formula to follow:

$$
totalOpenInterest < (depositedLiquidity * maxUtilizationPercentage)
$$

To be more accurate, we can account for the differences in longs/shorts. 

Shorts can never profit more than the original size of the position, therefore the shortOpenInterest is the maximum possible amount paid out to shorts. Longs however can increase in profit without bound, so we can account for the current valuation of total long positions.

$$
(shortOpenInterest) + (longOpenInterestInTokens * currentIndexTokenPrice) < (depositedLiquidity * maxUtilizationPercentage)
$$

Once a liquidity reserve validation such as the ones above have been implemented, trader’s cannot open positions past what is reasonably supported by the deposited liquidity and depositors cannot withdraw liquidity that is crucial for backing existing positions.

### Extra

Here are some references that may be useful to you as you research and implement your perpetual futures protocol: 

- [GMX V2 Documentation](https://gmx-docs.io/docs/trading/v2)
- [GMX V2 Technical Overview](https://www.youtube.com/watch?v=58om-oA1vpI) (Video)
- [Exclusive GMX V2 Deep Dive](https://drive.google.com/drive/u/1/folders/1Ykv3mRcPkOZz064spxUObxdC6xVgGyua) (More in-depth)