import { network } from "hardhat";

function getArg(flag: string, envKey: string, fallback: string): string {
  const idx = process.argv.indexOf(flag);
  if (idx !== -1 && process.argv[idx + 1]) return process.argv[idx + 1];
  const v = process.env[envKey];
  return v && v.length > 0 ? v : fallback;
}

// Deploys contracts/MyNFT.sol with provided name/symbol
async function main() {
  const name = getArg("--name", "NFT_NAME", "MyNFT");
  const symbol = getArg("--symbol", "NFT_SYMBOL", "MNFT");

  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const chainId = await pc.getChainId();

  console.log("ChainId:", chainId);
  console.log("Deployer:", deployer.account.address);
  console.log("Deploying MyNFT:", { name, symbol });

  const nft = await viem.deployContract("MyNFT", [name, symbol]);
  console.log("MyNFT deployed at:", nft.address);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
