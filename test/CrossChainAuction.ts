import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { encodeAbiParameters, parseAbiParameters } from "viem";
// Simulate a cross-chain ERC20 bid via CCIP receiver by directly
// calling ccipReceive with a crafted message and pre-funded tokens.
describe("Cross-chain Auction via CCIP (ERC20)", async function () {
    const { viem } = await network.connect();
    const publicClient = await viem.getPublicClient();
    const [seller, routerLike, sourceSender] = await viem.getWalletClients();
    it("places an ERC20 bid using CCIP receiver", async function () {
        // Deploy NFT and mint to seller
        const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
        await nft.write.mint([seller.account.address]);
        const tokenId = 1n;

        // Deploy ERC20 and AuctionFactory
        const erc20 = await viem.deployContract("TestERC20", ["TestToken", "TTK"]);
        const factory = await viem.deployContract("AuctionFactory");

        // Create ERC20 auction
        await nft.write.approve([factory.address, tokenId], { account: seller.account });
        const startingPrice = 100n * 10n ** 18n;
        const duration = 120n;
        await factory.write.createAuction([
            nft.address,
            tokenId,
            erc20.address,
            startingPrice,
            duration,
        ], { account: seller.account });
        const auctionAddr = await factory.read.getAuction([nft.address, tokenId]);
        const auction = await viem.getContractAt("Auction", auctionAddr);

        // Deploy CCIP receiver with router set to routerLike account
        const receiver = await viem.deployContract("CrossChainBidReceiver", [routerLike.account.address]);
        // Allow a source sender (bytes-encoded) from a given chain selector
        const chainSelector = 16015286601757825753n; // example selector (Ethereum Sepolia)
        const sourceSenderBytes = encodeAbiParameters(
            parseAbiParameters("address"),
            [sourceSender.account.address]
        );
        await receiver.write.setAllowedSender([chainSelector, sourceSenderBytes, true], { account: seller.account });

        // Pre-fund receiver with ERC20 to simulate bridged tokens arrival
        const bridgedAmount = startingPrice + 50n; // higher than starting price
        await erc20.write.mint([receiver.address, bridgedAmount]);
        // Build CCIP message
        const message = {
            messageId: `0x${"11".padEnd(64, "0")}` as `0x${string}`,
            sourceChainSelector: chainSelector,
            sender: sourceSenderBytes as `0x${string}`,
            data: encodeAbiParameters(
                parseAbiParameters("address,address,uint256,address"),
                [auction.address, erc20.address, bridgedAmount, sourceSender.account.address]
            ),
            destTokenAmounts: [
                { token: erc20.address, amount: bridgedAmount },
            ],
        } as any;
        // Call ccipReceive from the designated router address
        await receiver.write.ccipReceive([message], { account: routerLike.account });

        // Highest bid updated; bidder recorded as local recipient
        const highestBid = await auction.read.highestBid();
        const highestBidder = await auction.read.highestBidder();
        assert.equal(highestBid, bridgedAmount);
        assert.equal(highestBidder.toLowerCase(), sourceSender.account.address.toLowerCase());
    });
});