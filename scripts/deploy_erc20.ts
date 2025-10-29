import { network } from "hardhat";

function getArg(flag: string, envKey: string, fallback: string): string {
  const idx = process.argv.indexOf(flag);
  if (idx !== -1 && process.argv[idx + 1]) return process.argv[idx + 1];
  const v = process.env[envKey];
  return v && v.length > 0 ? v : fallback;
}

// Deploys contracts/TestERC20.sol with provided name/symbol
async function main() {
  const name = getArg("--name", "ERC20_NAME", "TestToken");
  const symbol = getArg("--symbol", "ERC20_SYMBOL", "TT");

  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const chainId = await pc.getChainId();

  console.log("ChainId:", chainId);
  console.log("Deployer:", deployer.account.address);
  console.log("Deploying TestERC20:", { name, symbol });

  const erc20 = await viem.deployContract("TestERC20", [name, symbol]);
  console.log("TestERC20 deployed at:", erc20.address);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
