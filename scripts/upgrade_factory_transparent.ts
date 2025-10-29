import { network } from "hardhat";

async function main() {
  const proxyAdmin = process.env.PROXY_ADMIN as `0x${string}` | undefined;
  const factoryProxy = process.env.FACTORY_PROXY as `0x${string}` | undefined;
  if (!proxyAdmin || !factoryProxy) throw new Error("Set PROXY_ADMIN and FACTORY_PROXY for Transparent upgrade");

  const { viem } = await network.connect();
  const [admin] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const chainId = await pc.getChainId();

  console.log("ChainId:", chainId);
  console.log("Admin:", admin.account.address);
  console.log("ProxyAdmin:", proxyAdmin);
  console.log("Factory proxy:", factoryProxy);

  // Deploy new implementation
  const impl = await viem.deployContract("AuctionFactoryTransparent");
  console.log("New impl:", impl.address);

  // Use ProxyAdmin to upgrade
  const pa = await viem.getContractAt("ProxyAdminDeployer", proxyAdmin);
  const tx = await pa.write.upgrade([factoryProxy, impl.address]);
  await pc.waitForTransactionReceipt({ hash: tx });
  console.log("upgrade tx:", tx);

  // Optional: check via calling version() on proxy using new ABI
  const proxyAsFactory = await viem.getContractAt("AuctionFactoryTransparent", factoryProxy);
  const ver = await proxyAsFactory.read.version();
  console.log("Factory version:", ver);
}

main().catch((e) => { console.error(e); process.exit(1); });

