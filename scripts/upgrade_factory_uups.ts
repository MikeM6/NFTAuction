import { network } from "hardhat";
import { encodeFunctionData } from "viem";

async function main() {
  const proxyAddress = process.env.FACTORY_PROXY as `0x${string}` | undefined;
  if (!proxyAddress) throw new Error("Set FACTORY_PROXY to the UUPS proxy address");

  const { viem } = await network.connect();
  const [owner] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const chainId = await pc.getChainId();

  console.log("ChainId:", chainId);
  console.log("Owner:", owner.account.address);
  console.log("Upgrading UUPS factory proxy:", proxyAddress);

  // Deploy new implementation
  const impl = await viem.deployContract("AuctionFactoryUUPS");
  console.log("New impl:", impl.address);

  // Some artifacts may omit inherited UUPS functions from ABI in this setup.
  // Encode and send upgradeTo directly via wallet client.
  const uupsAbi = [
    {
      type: "function",
      name: "upgradeTo",
      stateMutability: "nonpayable",
      inputs: [{ name: "newImplementation", type: "address" }],
      outputs: [],
    },
  ] as const;
  const data = encodeFunctionData({ abi: uupsAbi, functionName: "upgradeTo", args: [impl.address as `0x${string}`] });
  const tx = await owner.sendTransaction({ to: proxyAddress, data });
  await pc.waitForTransactionReceipt({ hash: tx });
  console.log("upgradeTo tx:", tx);

  // Optional: check version
  const proxyAsFactory = await viem.getContractAt("AuctionFactoryUUPS", proxyAddress);
  const ver = await proxyAsFactory.read.version();
  console.log("Factory version:", ver);
}

main().catch((e) => { console.error(e); process.exit(1); });
