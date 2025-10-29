import { network } from "hardhat";

function must(key: string): string {
  const v = process.env[key];
  if (!v || !v.trim()) throw new Error(`Missing required env: ${key}`);
  return v.trim();
}

function opt(key: string): string | undefined {
  const v = process.env[key];
  return v && v.trim().length > 0 ? v.trim() : undefined;
}

function toBI(name: string, v: string): bigint {
  try { return v.startsWith("0x") ? BigInt(v) : BigInt(v); } catch { throw new Error(`${name} must be numeric`); }
}

async function main() {
  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();

  const factoryAddr = must("FACTORY_ADDRESS") as `0x${string}`;
  const nft = must("NFT_ADDRESS") as `0x${string}`;
  const tokenId = toBI("TOKEN_ID", must("TOKEN_ID"));
  const currency = (opt("CURRENCY_ADDRESS") as `0x${string}`) ?? ("0x0000000000000000000000000000000000000000" as const);
  const startingPrice = toBI("STARTING_PRICE_WEI", must("STARTING_PRICE_WEI"));
  const duration = toBI("DURATION_SECONDS", must("DURATION_SECONDS"));

  console.log("Deployer:", deployer.account.address);
  console.log("Factory:", factoryAddr);
  console.log("Creating auction:", { nft, tokenId: tokenId.toString(), currency, startingPriceWei: startingPrice.toString(), duration: duration.toString() });

  const abiName = (process.env.FACTORY_ABI || "AuctionFactory") as string;
  const factory = await viem.getContractAt(abiName, factoryAddr);
  const hash = await factory.write.createAuction([nft, tokenId, currency, startingPrice, Number(duration)]);
  const receipt = await pc.waitForTransactionReceipt({ hash });
  console.log("createAuction tx:", hash);

  // Read created auction address from mapping
  const auction = await factory.read.getAuction([nft, tokenId]) as `0x${string}`;
  console.log("Auction created at:", auction);
  console.log("Note: Ensure you approved the Factory to transfer the NFT before creation (ERC721.approve or setApprovalForAll). ");
}

main().catch((e) => { console.error(e); process.exit(1); });
