import { network } from "hardhat";
async function main() {
    const { viem } = await network.connect();
    const [deployer] = await viem.getWalletClients();
    const pc = await viem.getPublicClient();
    const chainId = await pc.getChainId();
    console.log("ChainId:", chainId);
    console.log("Deployer:", deployer.account.address);
    console.log("Deploying AuctionFactory...");
    const factory = await viem.deployContract("AuctionFactory");
    console.log("AuctionFactory deployed at:", factory.address);
}
main().catch((e) => {
    console.error(e);
    process.exit(1);
});