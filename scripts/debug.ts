import { network } from "hardhat";

const connection = await network.connect();
console.log("connection keys:", Object.keys(connection));
// @ts-ignore
console.log("viem type:", typeof (connection as any).viem);

