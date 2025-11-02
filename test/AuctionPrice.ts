import assert from "node:assert/strict";
import { describe, it, before } from "node:test";

import { network } from "hardhat";

describe("Auction USD conversion (Chainlink)", function () {
  let viem: any;
  let publicClient: any;
  let seller: any;
  let bidder: any;

  before(async () => {
    const conn = await network.connect();
    viem = conn.viem;
    publicClient = await viem.getPublicClient();
    [seller, bidder] = await viem.getWalletClients();
  });

  it("ETH amountInUsd and currentHighestBidInUsd", async function () {
    // Deploy NFT and mint
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;

    // Deploy factory and create ETH auction
    const factory = await viem.deployContract("AuctionFactory");
    await nft.write.approve([factory.address, tokenId], { account: seller.account });
    const duration = 60n;
    await factory.write.createAuction([
      nft.address,
      tokenId,
      "0x0000000000000000000000000000000000000000",
      0n,
      duration,
    ], { account: seller.account });

    const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
    const auction = await viem.getContractAt("Auction", auctionAddr);

    // Deploy Chainlink mock and set feeds (ETH/USD = 3000, 8 decimals)
    const feed = await viem.deployContract("MockAggregatorV3", [8, 3000n * 10n ** 8n]);
    await auction.write.setPriceFeeds([feed.address, "0x0000000000000000000000000000000000000000"], { account: seller.account });

    // amountInUsd for 2 ETH => 6000 USD (8 decimals)
    const [usd, dec] = await auction.read.amountInUsd([2n * 10n ** 18n]);
    assert.equal(dec, 8);
    assert.equal(usd, 6000n * 10n ** 8n);

    // place a bid of 1.5 ETH and check
    await auction.write.bid({ account: bidder.account, value: 15n * 10n ** 17n });
    const [usdBid, decBid] = await auction.read.currentHighestBidInUsd();
    assert.equal(decBid, 8);
    assert.equal(usdBid, 3000n * 10n ** 8n * 15n / 10n); // 4500 * 1e8
  });

  it("ERC20 amountInUsd with token/USD feed", async function () {
    // NFT
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;

    // ERC20 and factory
    const erc20 = await viem.deployContract("TestERC20", ["TestToken", "TTK"]);
    const factory = await viem.deployContract("AuctionFactory");

    await nft.write.approve([factory.address, tokenId], { account: seller.account });

    await factory.write.createAuction([
      nft.address,
      tokenId,
      erc20.address,
      0n,
      60n,
    ], { account: seller.account });
    const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
    const auction = await viem.getContractAt("Auction", auctionAddr);

    // token/USD = 2.25 with 8 decimals
    const tokenFeed = await viem.deployContract("MockAggregatorV3", [8, 225_000_000n]);
    await auction.write.setPriceFeeds(["0x0000000000000000000000000000000000000000", tokenFeed.address], { account: seller.account });

    // 100 tokens (18 decimals) => 225 USD (8 decimals)
    const [usd, dec] = await auction.read.amountInUsd([100n * 10n ** 18n]);
    assert.equal(dec, 8);
    assert.equal(usd, 225_000_00000n);
  });

  it("reverts when feed not set or no bid", async function () {
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;
    const factory = await viem.deployContract("AuctionFactory");
    await nft.write.approve([factory.address, tokenId], { account: seller.account });
    await factory.write.createAuction([nft.address, tokenId, "0x0000000000000000000000000000000000000000", 0n, 60n], { account: seller.account });
    const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
    const auction = await viem.getContractAt("Auction", auctionAddr);

    // feed not set
    await assert.rejects(async () => {
      await auction.read.amountInUsd([10n ** 18n]);
    });

    // set feed but no bid -> currentHighestBidInUsd reverts
    const feed = await viem.deployContract("MockAggregatorV3", [8, 1000n * 10n ** 8n]);
    await auction.write.setPriceFeeds([feed.address, "0x0000000000000000000000000000000000000000"], { account: seller.account });
    await assert.rejects(async () => {
      await auction.read.currentHighestBidInUsd();
    });
  });
});
