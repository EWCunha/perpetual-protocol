# Side Quest #1 - Yul & Memory

**Goal**

Understand how memory works in the EVM at a deep level & feel comfortable with Yul/inline assembly blocks.

**Instructions**

Yul is a lower level language used to interact with the EVM, it more directly allows you to interface with the opcodes defined in the [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf). In fact, Solidity is compiled down to Yul for intermediate optimizations before it is finally compiled down to raw bytecode which can be used by the EVM.

In this side quest you’re going to solidify your understanding of the EVM, Yul, and memory and use this knowledge to answer some questions about the Solady `SafeTransferLib` library.

Firstly, you should start off with these materials to build up your understanding of the EVM, Yul, and memory:

- [Introduction to the EVM](https://www.youtube.com/watch?v=Ru3inmu1FuQ) (Video)
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) (Read the opcodes from page 30-38)
- [Focus on memory](https://www.youtube.com/watch?v=9qLUvtL5uKQ) (Video)
- [Everything you need to know about memory](https://twitter.com/0xOwenThurm/status/1661506159348690949) (Thread)

You can commit your answers to the questions below in a `SideQuest1.md` file to your team perpetuals repo.

**Questions**

For the following questions, you’ll look at the [SafeTransferLib](https://github.com/Vectorized/solady/blob/efd63173997c6e30a2e45cd889cdd3968598a4c2/src/utils/SafeTransferLib.sol) from the Solady repo.

We’ll go over the `balanceOf` function together to get an initial understanding, the following questions pertain to the `safeTransferFrom`, `safeTransfer`, and `safeApprove` functions.

1. In the safeTransferFrom function, what does `0x23b872dd000000000000000000000000` represent and what does it mean when used in the following context on line 192: `mstore(0x0c, 0x23b872dd000000000000000000000000)`.

2. In the ` ` function, why is `shl` used on line 191 to shift the `from` to the left by 96 bits?

3. In the `safeTransferFrom` function, is this memory safe assembly? Why or why not?

4. In the `safeTransferFrom` function, on line 197, why is 0x1c provided as the 4th argument to `call`?

5. In the `safeTransfer` function, on line 266, why is `revert` used with `0x1c` and `0x04`.

6. In the `safeTransfer` function, on line 268, why is `0` mstore’d at `0x34`.

7. In the `safeApprove` function, on line 317, why is `mload(0x00)` validated for equality to 1?

8. In the `safeApprove` function, if the `token` returns `false` from the `approve(address,uint256)` function, what happens?