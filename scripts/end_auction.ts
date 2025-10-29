import { network } from "hardhat";

function must(key: string): string {
  const v = process.env[key];
  if (!v || !v.trim()) throw new Error(`Missing required env: ${key}`);
  return v.trim();
}

async function main() {
  const { viem } = await network.connect();
  const [caller] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();
  const auctionAddr = must("AUCTION_ADDRESS") as `0x${string}`;
  const auction = await viem.getContractAt("Auction", auctionAddr);
  const hash = await auction.write.end([]);
  await pc.waitForTransactionReceipt({ hash });
  console.log("end() tx:", hash);
}

main().catch((e) => { console.error(e); process.exit(1); });

