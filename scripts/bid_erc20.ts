import { network } from "hardhat";
import { parseUnits } from "viem";

function must(key: string): string {
  const v = process.env[key];
  if (!v || !v.trim()) throw new Error(`Missing required env: ${key}`);
  return v.trim();
}

async function main() {
  const { viem } = await network.connect();
  const [bidder] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();

  const auctionAddr = must("AUCTION_ADDRESS") as `0x${string}`;
  const erc20Addr = must("ERC20_ADDRESS") as `0x${string}`;
  const amountHuman = must("BID_AMOUNT");

  console.log("Bidder:", bidder.account.address);
  console.log("Auction:", auctionAddr);
  console.log("ERC20:", erc20Addr, "amount:", amountHuman);

  const erc20 = await viem.getContractAt("TestERC20", erc20Addr);
  const decimals = (await erc20.read.decimals()) as number;
  const amount = parseUnits(amountHuman, decimals);

  // approve
  const approveHash = await erc20.write.approve([auctionAddr, amount]);
  await pc.waitForTransactionReceipt({ hash: approveHash });
  console.log("approve tx:", approveHash);

  const auction = await viem.getContractAt("Auction", auctionAddr);
  const bidHash = await auction.write.bidERC20([amount]);
  await pc.waitForTransactionReceipt({ hash: bidHash });
  console.log("bidERC20 tx:", bidHash);
}

main().catch((e) => { console.error(e); process.exit(1); });

