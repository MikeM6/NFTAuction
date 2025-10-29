import { network } from "hardhat";
import { parseUnits } from "viem";

// Reads env var, trims, returns undefined if empty
function env(key: string): string | undefined {
  const v = process.env[key]?.trim();
  return v ? v : undefined;
}

// Mints one MyNFT token to `to`
async function mintNft(viem: any, to: `0x${string}`, nftAddress: `0x${string}`) {
  const nft = await viem.getContractAt("MyNFT", nftAddress);
  const hash = await nft.write.mint([to]);
  const pc = await viem.getPublicClient();
  const receipt = await pc.waitForTransactionReceipt({ hash });
  // best-effort read the latest tokenId (MyNFT exposes nextTokenId)
  const next = (await nft.read.nextTokenId()) as bigint;
  const mintedId = next; // nextTokenId equals the last minted id
  console.log("[NFT] tx:", hash);
  console.log("[NFT] minted tokenId:", mintedId.toString());
  console.log("[NFT] to:", to);
  console.log("[NFT] contract:", nftAddress);
  return { hash, receipt, tokenId: mintedId };
}

// Mints ERC20 tokens to `to` with human-readable amount
async function mintErc20(
  viem: any,
  to: `0x${string}`,
  erc20Address: `0x${string}`,
  humanAmount: string
) {
  const erc20 = await viem.getContractAt("TestERC20", erc20Address);
  const decimals = (await erc20.read.decimals()) as number;
  const amount = parseUnits(humanAmount, decimals);
  const hash = await erc20.write.mint([to, amount]);
  const pc = await viem.getPublicClient();
  const receipt = await pc.waitForTransactionReceipt({ hash });
  console.log("[ERC20] tx:", hash);
  console.log("[ERC20] minted:", humanAmount, "(decimals:", decimals, ")");
  console.log("[ERC20] to:", to);
  console.log("[ERC20] contract:", erc20Address);
  return { hash, receipt };
}

async function main() {
  const nftAddress = env("NFT_ADDRESS");
  const erc20Address = env("ERC20_ADDRESS");
  const erc20Amount = env("ERC20_MINT_AMOUNT") ?? "1000"; // human units
  const toEnv = env("MINT_TO");

  if (!nftAddress && !erc20Address) {
    console.log("Nothing to mint. Set env vars NFT_ADDRESS and/or ERC20_ADDRESS.");
    console.log(
      "Examples (PowerShell): $env:NFT_ADDRESS=0x...; npx hardhat run scripts/mint.ts --network sepolia"
    );
    process.exit(1);
  }

  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const chainId = await pc.getChainId();

  const to = (toEnv as `0x${string}`) ?? (deployer.account.address as `0x${string}`);
  console.log("ChainId:", chainId);
  console.log("Deployer:", deployer.account.address);
  console.log("Mint to:", to);

  if (nftAddress) {
    await mintNft(viem, to, nftAddress as `0x${string}`);
  }

  if (erc20Address) {
    await mintErc20(viem, to, erc20Address as `0x${string}`, erc20Amount);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
