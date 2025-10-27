import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

describe("Auction (ETH & ERC20)", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [seller, bidder1, bidder2] = await viem.getWalletClients();

  it("ETH auction end-to-end", async function () {
    // deploy NFT
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);

    // mint NFT to seller
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;

    // deploy factory
    const factory = await viem.deployContract("AuctionFactory");

    // approve factory to move NFT
    await nft.write.approve([factory.address, tokenId], { account: seller.account });

    // create auction (ETH currency -> address(0))
    const startingPrice = 1_000_000_000_000_000n; // 0.001 ETH
    const duration = 5n; // 5 seconds
    await factory.write.createAuction([
      nft.address,
      tokenId,
      "0x0000000000000000000000000000000000000000",
      startingPrice,
      duration,
    ], { account: seller.account });

    const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
    assert.ok(auctionAddr !== "0x0000000000000000000000000000000000000000");

    // bidder1 places a bid
    const auction = await viem.getContractAt("Auction", auctionAddr);

    await auction.write.bid({ account: bidder1.account, value: startingPrice });

    // bidder2 outbids
    await auction.write.bid({ account: bidder2.account, value: startingPrice + 1n });

    // wait for auction to end
    const endTime = await auction.read.endTime();
    const now = await publicClient.getBlock();
    if (now.timestamp < endTime) {
      const delta = Number(endTime - now.timestamp + 1n);
      // use raw JSON-RPC to manipulate time on Hardhat Network
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_increaseTime", params: [delta] });
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_mine", params: [] });
    }

    await auction.write.end();

    // verify NFT ownership
    assert.equal((await nft.read.ownerOf([tokenId])).toLowerCase(), bidder2.account.address.toLowerCase());
  });

  it("ERC20 auction end-to-end", async function () {
    // deploy NFT
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;

    // deploy ERC20 and mint to bidders
    const erc20 = await viem.deployContract("TestERC20", ["TestToken", "TTK"]);
    await erc20.write.mint([bidder1.account.address, 10_000n * 10n ** 18n]);
    await erc20.write.mint([bidder2.account.address, 10_000n * 10n ** 18n]);

    // deploy factory
    const factory = await viem.deployContract("AuctionFactory");

    // approve factory to transfer NFT
    await nft.write.approve([factory.address, tokenId], { account: seller.account });

    const startingPrice = 100n * 10n ** 18n;
    const duration = 5n;

    await factory.write.createAuction([
      nft.address,
      tokenId,
      erc20.address,
      startingPrice,
      duration,
    ], { account: seller.account });

    const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
    const auction = await viem.getContractAt("Auction", auctionAddr);

    // bidders approve auction to pull funds
    await erc20.write.approve([auction.address, startingPrice], { account: bidder1.account });
    await erc20.write.approve([auction.address, startingPrice + 1n], { account: bidder2.account });

    // place bids
    await auction.write.bidERC20([startingPrice], { account: bidder1.account });
    await auction.write.bidERC20([startingPrice + 1n], { account: bidder2.account });

    // fast forward time and end
    const endTime = await auction.read.endTime();
    const now = await publicClient.getBlock();
    if (now.timestamp < endTime) {
      const delta = Number(endTime - now.timestamp + 1n);
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_increaseTime", params: [delta] });
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_mine", params: [] });
    }

    // record seller balance before
    const sellerBalBefore = await erc20.read.balanceOf([seller.account.address]);

    await auction.write.end();

    // NFT goes to highest bidder (bidder2)
    assert.equal((await nft.read.ownerOf([tokenId])).toLowerCase(), bidder2.account.address.toLowerCase());

    // seller received payment
    const sellerBalAfter = await erc20.read.balanceOf([seller.account.address]);
    assert.equal(sellerBalAfter - sellerBalBefore, startingPrice + 1n);
  });
});
