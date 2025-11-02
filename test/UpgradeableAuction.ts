import assert from "node:assert/strict";
import { describe, it, before } from "node:test";

import { network } from "hardhat";

// UUPS and Transparent proxy upgrade flows for Auction
describe("Upgradeable Auction (UUPS & Transparent)", function () {
  let viem: any;
  let publicClient: any;
  let seller: any;
  let bidder1: any;
  let bidder2: any;
  let admin: any;

  before(async () => {
    const conn = await network.connect();
    viem = conn.viem;
    publicClient = await viem.getPublicClient();
    [seller, bidder1, bidder2, admin] = await viem.getWalletClients();
  });

  it("UUPS: end-to-end and upgrade", async function () {
    // Deploy NFT and mint to seller
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    await nft.write.mint([seller.account.address]);
    const tokenId = 1n;

    // Deploy UUPS implementation
    const impl = await viem.deployContract("AuctionUUPS");

    // Deploy ERC1967Proxy with empty data, then initialize via proxy
    const proxy = await viem.deployContract("ERC1967ProxyDeployer", [impl.address, "0x"]);
    const auction = await viem.getContractAt("AuctionUUPS", proxy.address);

    const duration = 3600n;
    const endBlock = await publicClient.getBlock();
    const endTime = BigInt(endBlock.timestamp) + duration;

    await auction.write.initialize([
      seller.account.address,
      nft.address,
      tokenId,
      "0x0000000000000000000000000000000000000000",
      1_000_000_000_000_000n, // 0.001 ETH
      endTime,
    ], { account: seller.account });

    // Transfer NFT into auction
    await nft.write.safeTransferFrom([
      seller.account.address,
      auction.address,
      tokenId,
    ], { account: seller.account });

    // Bids
    await auction.write.bid({ account: bidder1.account, value: 1_000_000_000_000_000n });
    await auction.write.bid({ account: bidder2.account, value: 1_000_000_000_000_001n });

    // Advance time and end
    const now = await publicClient.getBlock();
    if (BigInt(now.timestamp) < endTime) {
      const delta = Number(endTime - BigInt(now.timestamp) + 1n);
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_increaseTime", params: [delta] });
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_mine", params: [] });
    }
    await auction.write.end();

    // Ownership moved to highest bidder
    assert.equal((await nft.read.ownerOf([tokenId])).toLowerCase(), bidder2.account.address.toLowerCase());

    // Upgrade to V2 via UUPS (seller is owner)
    const v2 = await viem.deployContract("AuctionUUPSV2");
    // 在实现合约中调用upgradeToAndCall方法升级合约，使代理合约指向V2实现合约
    await auction.write.upgradeToAndCall([v2.address, "0x"], { account: seller.account });

    // Call new function through proxy
    const auctionV2 = await viem.getContractAt("AuctionUUPSV2", auction.address);
    const ver = await auctionV2.read.version();
    assert.equal(ver, 2n);
  });

  it("Transparent: end-to-end and upgrade", async function () {
    // NFT + ERC20 setup
    const nft = await viem.deployContract("MyNFT", ["MyNFT", "MNFT"]);
    const erc20 = await viem.deployContract("TestERC20", ["TestToken", "TTK"]);
    await nft.write.mint([seller.account.address]);
    await erc20.write.mint([bidder1.account.address, 10_000n * 10n ** 18n]);
    await erc20.write.mint([bidder2.account.address, 10_000n * 10n ** 18n]);
    const tokenId = 1n;

    // Deploy implementation and transparent proxy (admin is a dedicated account)
    const impl = await viem.deployContract("AuctionTransparent");
    // 部署代理合约
    const proxy = await viem.deployContract("TransparentUpgradeableProxyDeployer", [impl.address, admin.account.address, "0x"]);
    const auction = await viem.getContractAt("AuctionTransparent", proxy.address);

    const duration = 3600n;
    const endBlock = await publicClient.getBlock();
    const endTime = BigInt(endBlock.timestamp) + duration;

    // Initialize via proxy as seller (admin cannot call logic)
    await auction.write.initialize([
      seller.account.address,
      nft.address,
      tokenId,
      erc20.address,
      100n * 10n ** 18n,
      endTime,
    ], { account: seller.account });

    // Transfer NFT into auction
    await nft.write.safeTransferFrom([
      seller.account.address,
      auction.address,
      tokenId,
    ], { account: seller.account });

    // Approvals and bids (non-admin accounts)
    const et = await auction.read.endTime();
    const blk = await publicClient.getBlock();
    // eslint-disable-next-line no-console
    console.log("[Transparent] now:", String(blk.timestamp), "endTime:", String(et));
    await erc20.write.approve([auction.address, 100n * 10n ** 18n], { account: bidder1.account });
    await erc20.write.approve([auction.address, 101n * 10n ** 18n], { account: bidder2.account });
    await auction.write.bidERC20([100n * 10n ** 18n], { account: bidder1.account });
    await auction.write.bidERC20([101n * 10n ** 18n], { account: bidder2.account });

    // Advance and end
    const now = await publicClient.getBlock();
    if (BigInt(now.timestamp) < endTime) {
      const delta = Number(endTime - BigInt(now.timestamp) + 1n);
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_increaseTime", params: [delta] });
      // @ts-ignore
      await (publicClient as any).transport.request({ method: "evm_mine", params: [] });
    }
    const sellerBefore = await erc20.read.balanceOf([seller.account.address]);
    await auction.write.end();
    assert.equal((await nft.read.ownerOf([tokenId])).toLowerCase(), bidder2.account.address.toLowerCase());
    const sellerAfter = await erc20.read.balanceOf([seller.account.address]);
    assert.equal(sellerAfter - sellerBefore, 101n * 10n ** 18n);

    // Resolve auto-created ProxyAdmin address from EIP-1967 admin slot and upgrade (owner = admin)
    const ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
    // @ts-ignore
    const raw = await (publicClient as any).transport.request({ method: "eth_getStorageAt", params: [auction.address, ADMIN_SLOT, "latest"] });
    const proxyAdminAddr = "0x" + raw.slice(26);
    const pa = await viem.getContractAt("ProxyAdminDeployer", proxyAdminAddr);
    const v2 = await viem.deployContract("AuctionTransparentV2");
    // admin调用upgradeAndCall升级合约
    await pa.write.upgradeAndCall([
      auction.address,
      v2.address,
      "0x",
    ], { account: admin.account });

    const auctionV2 = await viem.getContractAt("AuctionTransparentV2", auction.address);
    const ver = await auctionV2.read.version();
    assert.equal(ver, 2n);
  });
});
