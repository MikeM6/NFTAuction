import { network } from "hardhat";
import { encodeFunctionData } from "viem";

// Deploy TransparentUpgradeableProxy for AuctionTransparent and AuctionFactoryTransparent
async function main() {
  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();

  // Deploy ProxyAdmin
  const proxyAdmin = await viem.deployContract("ProxyAdminDeployer", [deployer.account.address]);
  console.log("ProxyAdmin:", proxyAdmin.address);

  // Deploy implementations
  const auctionImpl = await viem.deployContract("AuctionTransparent");
  console.log("AuctionTransparent impl:", auctionImpl.address);
  const factoryImpl = await viem.deployContract("AuctionFactoryTransparent");
  console.log("FactoryTransparent impl:", factoryImpl.address);

  // Init data for AuctionTransparent
  const nft = "0x0000000000000000000000000000000000000001"; // placeholder
  const tokenId = 1n;
  const currency = "0x0000000000000000000000000000000000000000"; // ETH
  const startingPrice = 0n;
  const endTime = BigInt(Math.floor(Date.now() / 1000) + 3600);

  const auctionInit = encodeFunctionData({
    abi: auctionImpl.abi,
    functionName: "initialize",
    args: [
      deployer.account.address,
      nft,
      tokenId,
      currency,
      startingPrice,
      endTime,
    ],
  });
  const factoryInit = encodeFunctionData({
    abi: factoryImpl.abi,
    functionName: "initialize",
    args: [],
  });

  // Deploy transparent proxies
  const auctionProxy = await viem.deployContract("TransparentUpgradeableProxyDeployer", [
    auctionImpl.address,
    proxyAdmin.address,
    auctionInit,
  ]);
  console.log("AuctionTransparent proxy:", auctionProxy.address);

  const factoryProxy = await viem.deployContract("TransparentUpgradeableProxyDeployer", [
    factoryImpl.address,
    proxyAdmin.address,
    factoryInit,
  ]);
  console.log("FactoryTransparent proxy:", factoryProxy.address);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
