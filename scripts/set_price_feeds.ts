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

async function main() {
  const { viem } = await network.connect();
  const [owner] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();

  const auctionAddr = must("AUCTION_ADDRESS") as `0x${string}`;
  const ethUsdFeed = opt("ETH_USD_FEED") as `0x${string}` | undefined;
  const tokenUsdFeed = opt("TOKEN_USD_FEED") as `0x${string}` | undefined;

  if (!ethUsdFeed && !tokenUsdFeed) {
    throw new Error("Provide at least one of ETH_USD_FEED or TOKEN_USD_FEED");
  }

  const auction = await viem.getContractAt("Auction", auctionAddr);
  const hash = await auction.write.setPriceFeeds([
    ethUsdFeed ?? "0x0000000000000000000000000000000000000000",
    tokenUsdFeed ?? "0x0000000000000000000000000000000000000000",
  ]);
  await pc.waitForTransactionReceipt({ hash });
  console.log("setPriceFeeds tx:", hash);
}

main().catch((e) => { console.error(e); process.exit(1); });

