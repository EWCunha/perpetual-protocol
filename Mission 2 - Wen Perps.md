# Mission #2 - Wen Perps

# Motivation

During your first mission you laid the groundwork for a basic perpetuals protocol, we implemented:

- Liquidity providers depositing and withdrawing tokens that would “back” trader’s profits in exchange for benefitting from their losses.
- A way to get the realtime price of the asset being traded (or the *index token*). Perhaps you also implemented a price feed for the collateral token you chose to use.
- Trader’s have the ability to create a position, and increase it’s collateral and/or size.
- There is some validation such that trader’s cannot utilize more than a percentage of the current reserves — inversely, liquidity providers cannot withdraw reserved assets.

Now, your protocol team (yourself and your partner) is in deep development mode. The community is anxious, they want number to go up and they cannot stop asking, “wen!?”.

With Mission 2 you will complete your perpetuals protocol and have the Smart Contracts ready for launch with the basic features of a V1!

While you add the remaining features you will see how DeFi systems grow exponentially more complex as new functionalities are added. Perhaps more importantly you will see how it becomes increasingly easy to introduce vulnerabilities or bugs.

Yes, getting the Smart Contracts for a V1 perps protocol out in 2 weeks is quick. You should be proud of yourself for keeping up with such an endeavor and understand that you are *supposed* to make mistakes. We do not expect perfect perpetuals protocols after 2 weeks, otherwise you wouldn’t have much to learn!

# Goal & Deliverables

The second mission focuses on implementing the rest of the basic functionality of a decentralized perpetuals protocol.

Functionalities you should already have:

- A way to get the realtime price of the asset being traded.
- Traders can open a perpetual position for BTC, with a given size and collateral.
- Traders can increase the size of a perpetual position.
- Traders can increase the collateral of a perpetual position.
- Traders cannot utilize more than a configured percentage of the deposited liquidity.
- Liquidity providers cannot withdraw liquidity that is reserved for positions.

Functionalities to add with Mission 2:

- Traders can decrease the size of their position and realize a proportional amount of their PnL.
- Traders can decrease the collateral of their position.
- Individual position’s can be liquidated with a `liquidate` function, any address may invoke the `liquidate` function.
- A `liquidatorFee` is taken from the position’s remaining collateral upon liquidation with the `liquidate` function and given to the caller of the `liquidate` function.
- It is up to you whether the `liquidatorFee` is a percentage of the position’s remaining collateral or the position’s size, you should have a reasoning for your decision documented in the `README.md`.
- Traders can never modify their position such that it would make the position liquidatable.
- Traders are charged a `borrowingFee` which accrues as a function of their position size and the length of time the position is open.
- Traders are charged a `positionFee` from their collateral whenever they change the size of their position, the `positionFee` is a percentage of the position size delta (USD converted to collateral token). — Optional/Bonus

<aside>
💡 There are several gotcha’s with these added features, be sure you are considering all parts of the protocol and all possible edge cases when you implement them.

</aside>

# Details

## Decreasing a position

**Decrease size**

Similarly to increasing the size of a position, traders have the ability to decrease the size of their position, this includes closing their position (decreasing the size to 0).

However, decreasing a position is slightly more involved, we need to consider the PnL of the trader’s position when we are decreasing it.

If we don’t account for a trader’s PnL and allow them to decrease their size, they could manipulate their PnL and avoid paying losses! Additionally, decreasing the PnL this way reduces the probability that a trader will unexpectedly change the leverage of their remaining position drastically.

So we implement the following calculation when decreasing a position:

$$
realizedPnL = totalPositionPnL \cdot sizeDecrease\ /\  positionSize
$$

The `realizedPnL` is deducted from the position’s collateral if it is a loss, and paid out to the trader in the `collateralToken` if it is a profit.

This way, if a trader decreases their position’s size by 50%, they realize 50% of their PnL.

And if a trader closes their position (e.g. decreases by 100% of the size), they realize 100% of their PnL.

<aside>
💡 If a trader decreases the size of their position to 0, the position should be closed and the remaining collateral (after fees and losses) should be sent back to the trader.

</aside>

Example of decreasing a position’s size with positive PnL (trader is in profit):

- Bob opened his position when the index token price was $100, now the index token price is $110.
- Bob’s position has a size of 100 USD, sizeInTokens of 1, collateral of 50 USDC, and a current PnL of 10 USD — he’s up 10%!
- Bob decides to decrease his position size by 50 USD, e.g. 50% of his position.
- Therefore Bob realizes 50 / 100, 50% of his pending PnL
- `realizedPnl = totalPnl * sizeDecrease / positionSize = 10 * 50 / 100 = 5 USD`
- Bob receives 5 USDC for the 50% of the PnL he realized. This is paid from the LPs.
- Bob’s position now has a size of 50 USD, sizeInTokens of 0.5, collateral of 50 USDC, and a current PnL of 5 USD — he’s still up 10% on his *remaining* position.

Example of decreasing a position’s size with negative PnL (trader is in loss):

- Bob opened his position when the index token price was $100, now the index token price is $90.
- Bob’s position has a size of 100 USD, sizeInTokens of 1, collateral of 50 USDC, and a current PnL of -10 USD — he’s down 10%!
- Bob decides to decrease his position size by 50 USD, e.g. 50% of his position.
- Therefore Bob realizes 50 / 100, 50% of his pending PnL
- `realizedPnl = totalPnl * sizeDecrease / positionSize = -10 * 50 / 100 = -5 USD`
- Bob pays 5 USDC for the 50% of the PnL he realized. This is paid from his collateral.
- Bob’s position now has a size of 50 USD, sizeInTokens of 0.5, collateral of 45 USDC, and a current PnL of -5 USD — he’s still down 10% on his *remaining* position.

**Decrease collateral**

Just as trader’s are allowed to increase the collateral of their position, they should be allowed to decrease the collateral of their position.

If a trader has a position with 100 USDC as collateral, and chooses to remove 10 USDC from their collateral, they will receive 10 USDC and their position will be updated to have 90 USDC of collateral.

<aside>
💡 Traders may choose to decrease just the size of their position, just the collateral of their position, or both at the same time.

</aside>

## Liquidation

**What makes a position liquidatable?**

A position becomes liquidatable when it’s collateral is deemed insufficient to support the size of position that is open.

For our implementations we will use a *leverage* check to define whether a position is liquidatable or not:

$$
leverage = size / collateral
$$

Leverage is simply the ratio of the position’s size to the position’s collateral. For our protocol we will use an arbitrary `maxLeverage` which can be configured. The `maxLeverage` will be the cutoff point for the maximum leverage a position can have before it is considered liquidatable.

You might use 20x as a value for `maxLeverage` in your tests.

<aside>
💡 Be sure that traders can never modify their position and leave the position’s leverage over the maxLeverage (e.g. the position is liquidatable).

</aside>

**What occurs during liquidation?**

During liquidation, a position is force closed so that the protocol can remain *solvent*.

The following occurs:

- A position is force closed, e.g. size is decreased by 100%.
- Pending unrealized losses from PnL are paid from the position’s collateral.
- Fees such as the `positionFee` for closing 100% of the size are applied, as well as outstanding `borrowingFees`.
- A `liquidatorFee` is taken from the position’s remaining collateral and paid to the `msg.sender` who is invoking the `liquidate` function. It is up to you whether the `liquidatorFee` is a percentage of the remaining collateral or the position’s size, you should have a reasoning for your decision documented in the `README.md`.
- Any remaining collateral for the position is sent back to the user.

<aside>
💡 There are several potential edge cases surrounding liquidation:

- What if the position is being liquidated while in profit?
- What if the position does not have enough collateral to cover it’s losses/fees?
- What if a position is left with insufficient collateral to cover the liquidatorFee?

These are often edge cases that cause bugs and vulnerabilities in any DeFi protocol that involves liquidation (not limited to perpetuals). It is up to you to decide the best way to handle these edge cases.

</aside>

**How do liquidations happen?**

Liquidations occur when any position has surpassed the `maxLeverage` threshold and any arbitrary address calls the `liquidate` function specifying that particular position to liquidate.

Arbitrary actors are incentivized to initiate the liquidation as they are awarded the `liquidatorFee` for successfully liquidating a position.

You might have a `positionId` for positions, or position’s may identifiable based upon the trader’s address and the direction of the trade, or there may be some other mechanism for identifying positions. The caller of the `liquidate` function should simply be able to specify a position to liquidate.

<aside>
💡 Positions that are within the maxLeverage threshold should *not* be liquidatable, calls to the liquidate function for these positions should revert.

</aside>

## Fees

**Position Fees — Optional/Bonus**

A `positionFee` is applied when a position is increased or decreased, and is proportional to the amount of size that is increased or decreased.

The `positionFee` goes towards liquidity providers, this is one incentive for users to provide liquidity to the system.

The `positionFee` should be configurable by the owner, or trusted address — but bounded between the range of 0 to 200 basis points.

Example `positionFee` on increase:

- The `positionFee` is configured to 100 basis points.
- A trader opens a position with a size of 100 USD and 50 USDC for collateral.
- `positionFee = sizeDelta * 100 / 10_000 = 100 USD * 1% = 1 USD`
- The `positionFee` of 1 USD is subtracted from the collateral of the position and given to liquidity providers.
- The resulting position has a size of 100 USD and 49 USDC for collateral.
- The trader increases their position size by 50 USD.
- `positionFee = sizeDelta * 100 / 10_000 = 50 USD * 1% = 0.5 USD`
- The `positionFee` of 0.5 USD is subtracted from the collateral of the position and given to liquidity providers.
- The resulting position has a size of 150 USD and 48.5 USDC for collateral.

Example `positionFee` on decrease:

- The `positionFee` is configured to 100 basis points.
- A trader has a position with a size of 100 USD and 50 USDC for collateral, the trader’s position has a break-even PnL of 0 (the trader has neither gained nor lost any money, e.g. the *index token* price is the same as when the trader opened their position).
- The trader decreases their position size by 25 USDC.
- `positionFee = sizeDelta * 100 / 10_000 = 25 USD * 1% = 0.25 USD`
- The `positionFee` of 0.25 USD is subtracted from the collateral of the position and given to liquidity providers.
- The resulting position has a size of 75 USD and 49.75 USDC for collateral.
- The trader decreases their position size by 75 USDC.
- `positionFee = sizeDelta * 100 / 10_000 = 75 USD * 1% = 0.75 USD`
- The `positionFee` of 0.75 USD is subtracted from the collateral of the position and given to liquidity providers.
- The position is closed and the trader receives the remaining 49 USDC from their collateral.

<aside>
💡 100 basis points = 1%

</aside>

**Borrowing Fees**

Borrowing fees accrue over time in correspondence with the size of a position. The larger size a position has, the faster it’s borrowing fees will accrue. You can think of borrowing fees as a fee that the liquidity providers charge for the trader to “rent” reserved liquidity with their position.

Larger position’s will reserve more liquidity and so will accrue more borrowing fees.

Borrowing fees lend themselves nicely to a perSizePerSecond fee, e.g. the protocol defines a fee that accumulates per unit of size per second.

We will compute borrowing fees according to the following formula:

$$
borrowingFees = positionSize \cdot secondsSincePositionUpdated \cdot borrowingPerSharePerSecond
$$

We’ll define a reasonable `borrowingPerSharePerSecond` as one that allows for ≤ 10% of a position’s size to be charged over the course of a year. Given 31_536_000 seconds in a year this yields the following upper bound for the `borrowingPerSharePerSecond`.

$$
positionSize/10 = positionSize \cdot 31\_536\_000 \cdot borrowingPerSharePerSecond

$$

$$
\implies 1/borrowingPerSharePerSecond = 10 \ \cdot \ 31\_536\_000 
$$

$$
\implies borrowingPerSharePerSecond = 1/315\_360\_000

$$

To apply the `borrowingPerSharePerSecond` you’ll have to consider decimals, be sure your USD representation holds enough precision to avoid significant precision loss.

Here’s an example of how you might translate the above equation into solidity, accounting for decimals if your USD representation has 30 decimals of precision:

- `positionSize = 10_000 * 1e30`
- `secondsSincePositionUpdated = 31_536_000`
- `borrowingPerSharePerSecond = 1e30 / 315_360_000 = 3170979198376458650431` (~3.17e21)

$$
borrowingFees = 10\_000 \ \cdot \ 1e30 \ \cdot \ 31\_536\_000 \ \cdot \ 3170979198376458650431 /1e30
$$

$$
\implies borrowingFees = 1\_000 * 1e30
$$

<aside>
💡 Borrowing fees should be updated and paid every time a user modifies their position, or when a position is liquidated. 

All fees including borrowing fees should be taken into account when determining if a position is liquidatable.

</aside>

**Liquidation Fees**

Liquidation fees are intended to incentivize arbitrary addresses to maintain solvency for the protocol by liquidating positions *as soon as* they enter a liquidatable state. If position’s are not swiftly liquidated, they can take on more losses than the collateral can cover and end up insufficiently compensating LPs, or worse… causing unexpected bugs in the protocol.

A `liquidatorFee` is subtracted from the remaining collateral and sent to the `msg.sender` who invokes the `liquidate` function. It is up to you whether the `liquidatorFee` is a percentage of the remaining collateral or the position’s size, you should have a reasoning for your decision documented in the `README.md`.

You must also take into consideration the edge case where the remaining collateral for a liquidation is insufficient to cover the `liquidationFee`, this may affect your decision for the `liquidatorFee`. Document how this edge case is handled in the `README.md`.