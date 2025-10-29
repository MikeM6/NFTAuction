import { network } from "hardhat";
import { encodeFunctionData } from "viem";

// Deploy UUPS proxy for AuctionUUPS and AuctionFactoryUUPS using viem + OZ ERC1967Proxy
async function main() {
  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();

  // Deploy AuctionUUPS implementation
  const auctionImpl = await viem.deployContract("AuctionUUPS");
  console.log("AuctionUUPS impl:", auctionImpl.address);

  // Encode initializer
  const nft = "0x0ada5d29a30dc36f0fa3705fa0dd4c25ed023e1a"; // placeholder
  const tokenId = 1n;
  const currency = "0x0000000000000000000000000000000000000000"; // ETH
  const startingPrice = 0n;
  const endTime = BigInt(Math.floor(Date.now() / 1000) + 3600);

  const initData = encodeFunctionData({
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

  // Deploy proxy (ERC1967Proxy)
  const proxy = await viem.deployContract("ERC1967ProxyDeployer", [auctionImpl.address, initData]);
  console.log("AuctionUUPS proxy:", proxy.address);

  // Deploy FactoryUUPS implementation + proxy
  const factoryImpl = await viem.deployContract("AuctionFactoryUUPS");
  console.log("FactoryUUPS impl:", factoryImpl.address);
  const initFactory = encodeFunctionData({
    abi: factoryImpl.abi,
    functionName: "initialize",
    args: [],
  });
  const factoryProxy = await viem.deployContract("ERC1967ProxyDeployer", [factoryImpl.address, initFactory]);
  console.log("FactoryUUPS proxy:", factoryProxy.address);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
