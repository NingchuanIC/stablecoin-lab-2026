# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:

The risky part is that permission to mint also gives permission to destroy somebody else's tokens. A user could lose their balance without approving anything. However, the current Vault does not expose a function that lets any caller burn another person's tokens: `redeem` uses `msg.sender`. The Ex4 test impersonates the Vault to show that the token contract would accept such a burn. This is still a permission I would remove, because the token should enforce the user's consent itself.

I would keep `mint` restricted to `MINTER_ROLE`, but replace the privileged `burn(address,uint256)` with `burnFrom(address,uint256)` that checks and spends an allowance. Before redeeming, the user would approve the Vault for the amount of sUSD they want to redeem. Then `Vault.redeem` would call `stable.burnFrom(msg.sender, amount)` and return the same amount of collateral to that caller. A failed collateral transfer should revert the whole transaction, including the burn.

This adds an approval step, but makes the permission easier to understand. The Vault can only burn what a user has authorized, and approving an exact amount limits exposure. I would also test that redemption without approval fails and redemption with approval succeeds. This fixes the burn permission; preventing a minter from issuing unbacked coins is a separate problem.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:

Putting all three roles on one address is convenient for the lab, but I would not keep that setup in production. If that key is stolen, the attacker can create more minters, issue tokens, and pause the system. Losing one key should not give someone control over every part of the stablecoin.

I would give `DEFAULT_ADMIN_ROLE` to a timelock contract controlled by a multisignature wallet, for example one requiring three out of five independent signers. Changes such as adding a new minter should go through a timelock so users can see them before they take effect. A timelock would need to be added; the current contract does not provide one. After assigning the new holders, I would remove all three roles from the deployer's personal address.

Only the Vault should normally hold `MINTER_ROLE`, since its deposit function receives collateral before minting sUSD. There should be no everyday wallet that can mint directly. I would give `PAUSER_ROLE` to a separate emergency multisig with a smaller group that can respond quickly. Those signers should not automatically be able to grant minting rights.

The current pauser can also unpause. If restoring service should require the larger governance multisig, I would explicitly separate those permissions. Role separation reduces the damage from one compromised key, although it still depends on independent signers and secure key management.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:

I would keep redemption available by making the pause check depend on the type of balance change. In the current code, `whenNotPaused` is attached to `_update`, so it rejects transfers, minting, and burning in the same way. Since redemption requires burning sUSD, it fails even when the Vault has enough collateral.

My proposed rule would block ordinary transfers and new minting while paused, but allow a redemption burn made by the designated Vault. In `_update`, that exception would require a nonzero `from`, a zero `to`, and the token caller to be the Vault. I would combine this with the allowance-based `burnFrom` from A1. The Vault's public redemption function would still use its own caller as the token owner and send collateral back to that same person. Approval can remain available because it does not change token balances.

This avoids temporarily unpausing the whole token just to process one redemption. I would test that transfers and minting fail during a pause, an approved redemption succeeds, and burning another user's tokens without permission still fails.

There is a practical limit: if the bug is in redemption itself, keeping it open could make losses worse. I would therefore use a separate emergency control for redemption, with a clear reason for activating it, instead of making every pause freeze withdrawals automatically.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:

The main difference is whether holders still have a credible way to get their money back. In 2008, the Reserve Primary Fund reported a value of $0.97 per share and suspended redemption payments. This could avoid selling assets too quickly at poor prices, but it also left investors unable to exit when they wanted. For a stablecoin, that uncertainty would weaken confidence in the promise that one token is worth one dollar. The SEC describes the suspension in its [Reserve Fund FAQ](https://www.sec.gov/divisions/investment/guidance/reservefundmmffaq.htm).

USDC's case needs a small qualification: keeping the redemption promise did not mean instant dollar withdrawals throughout the weekend. Circle said the reserves held at Silicon Valley Bank would become available when banks reopened and reaffirmed redemption at one dollar per USDC. This is explained in its [March 2023 update](https://www.circle.com/pressroom/3-3-billion-of-usdc-reserve-risk-removed-dollar-de-peg-closes).

If eligible traders can buy discounted tokens and reliably redeem them for one dollar, they have a reason to buy, which can help restore the peg. However, this depends on actual access to reserves and enough liquidity. Keeping redemption open cannot replace missing assets, and it may let early users exit before others if reserves are insufficient. I would prefer continued redemption when reserves are sound, together with clear information about delays. A freeze may buy time, but it also removes an important reason for people to trust and hold the token.

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:

I would separate a shortage of backing from a problem with accessing backing. The first case happens when extra sUSD is minted without collateral, or collateral leaves the Vault without the matching tokens being burned. Then `totalCollateral() >= totalSupply()` becomes false. The Ex3 output shows this clearly: supply is 1,000,000 sUSD while collateral is zero. That demonstrates missing backing, although the local experiment does not measure an actual market price.

The second case is a blocked redemption channel. For example, calling `pause()` leaves the Vault's collateral balance and total supply unchanged, so the invariant can still pass. However, users cannot exchange their tokens for collateral. If they need cash or expect a long delay, they may accept a lower price on a market. Equal balances alone do not guarantee that the exit works.

There is also a valuation problem if a real collateral token falls below one dollar. Even with one collateral token for each sUSD, the dollar value of reserves would be too low. The current invariant compares token units, so it would miss that change. Both tokens having six decimals solves a unit conversion issue, not a price issue.

For these reasons, I would check reserve quantity, reserve value, and whether redemption actually works. Market liquidity and confidence also matter, so passing the accounting invariant is necessary for the intended backing model but does not prove a stable market price.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:

The attacker first obtains `MINTER_ROLE` and calls `SimpleStablecoin.mint` directly. Minting 1,000,000 sUSD means creating `1,000,000 * 10^6` smallest units. This increases the attacker's balance and total supply without transferring any MockUSDC into the Vault. The attacker has bypassed the normal deposit step.

Next, the attacker calls `Vault.redeem`. If the Vault holds at least 1,000,000 MockUSDC, it burns the attacker's sUSD and transfers that amount of collateral to them. The money comes from collateral deposited by other users. Their sUSD balances still exist, but less collateral remains to support them. Burning the attacker's coins does not repair the gap, because the same amount of collateral leaves at the same time.

The full redemption only works if the Vault has enough collateral. Otherwise, `InsufficientCollateral` makes the redemption revert before any burn or transfer. The tokens minted in the earlier transaction still exist, and the attacker could instead redeem a smaller amount to take the collateral that is available.

The best place to stop this is before granting minting rights: keep that role only on the Vault, remove the deployer's direct minting right, and protect role changes with a multisig and delay. Checks inside `deposit` cannot stop someone who calls the token's mint function directly. Emergency intervention might help after detection, but it could be too late and could also block honest users.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:

I would still write a backing invariant, but reading an on-chain balance would no longer be enough. A token representing US Treasuries is a claim on assets held elsewhere. Its balance does not by itself prove that those securities exist, belong to the reserve, or are free from other claims.

I would compare the conservative dollar value of verified reserves, after relevant costs and prior claims, with the dollar amount of sUSD outstanding. The calculation would need holdings records, current prices, accrued interest, and the correct decimals. Face value is not always the amount available today: Treasury prices can change with interest rates, and selling before maturity may produce a loss. The SEC's [bond risk explanation](https://www.investor.gov/introduction-investing/investing-basics/investment-products/bonds-or-fixed-income-products/bonds) describes this distinction.

The system would also need a custodian, independent checks of holdings, and an oracle to bring the information on-chain. I would reject stale price data for new minting rather than keep using an old value indefinitely. Still, an oracle can report a number without guaranteeing that the reserve can legally access the assets.

Finally, having enough asset value is different from having enough cash for today's redemptions. Sales and bank settlement take time, so I would keep a cash buffer and check short-term liquidity separately. The blockchain can verify the calculation, but the inputs and the right to sell the securities still depend on people and institutions.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:

I would not put a building into the Vault just by creating an NFT. I would first use a legal entity, such as a special purpose vehicle (SPV), to hold the property. Tokens could represent defined shares or claims against that entity. The documents would need to explain what holders receive, including rental income, sale proceeds, and rights if the issuer fails. The exact arrangement depends on the jurisdiction; transferring a token should not be assumed to transfer registered property ownership automatically.

The Vault could accept those tokens as collateral, but I would change the simple one-to-one model. A building needs a conservative valuation and a larger collateral buffer because its price is uncertain and it can take a long time to sell. Splitting ownership into small tokens does not guarantee buyers will be available. BIS also discusses this liquidity problem in its [research on real estate tokenisation](https://www.bis.org/publications/working-paper-1311-when-bricks-meet-bytes-does-tokenisation-fill-gaps-traditional-real-estate-markets).

Off-chain roles would include lawyers to establish the claim, the land registry to record title, a property manager to handle rent and maintenance, independent valuers, and an auditor to check accounts and existing mortgages. An oracle would pass valuation updates to the contract. The design may also need identity checks and transfer restrictions.

I would make the redemption and default rules clear in advance. A smart contract cannot sell a building instantly or enforce a disputed claim by itself, so cash reserves, sale procedures, and legal enforcement remain part of the system.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:

I would pick a leaked administrator key followed by unbacked minting and redemption. In the current contract, the administrator already holds `MINTER_ROLE`, so an attacker with that key could mint sUSD directly without depositing collateral. They could also grant minting permission to another address. If the Vault still holds collateral deposited by honest users, the attacker could redeem the new tokens and take that collateral. A redemption larger than the available balance would revert, but smaller withdrawals could still drain what is there.

I picked this because the attacker would not need to find a complicated bug in the transfer logic. The contract would accept the transactions as authorized. The test showing that a non-minter cannot mint would still pass, even though the stolen key gives the attacker minting rights. This is why checking the role modifier is only part of checking the system's security.

I would reduce this risk by removing the deployer's minting role after setup, allowing only the Vault to mint, and putting administrative role changes behind a multisig and timelock. An extra test could demonstrate the loss of backing after granting an attacker `MINTER_ROLE`. It would show why protecting the role assignment matters as much as rejecting an unauthorized caller.
