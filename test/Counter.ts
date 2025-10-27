import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

describe("Counter", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  // 3️⃣ 第一个测试：事件触发测试
  // ✅ 目的：检查 inc() 调用后是否触发 Increment 事件，且参数为 1n（BigInt 类型）

  // counter.write.inc()：调用合约的写入函数（修改状态）
  // emitWithArgs(...)：断言该交易触发了指定事件和参数
  it("Should emit the Increment event when calling the inc() function", async function () {
    const counter = await viem.deployContract("Counter");

    await viem.assertions.emitWithArgs(
      counter.write.inc(),
      counter,
      "Increment",
      [1n],
    );
  });


  //   4️⃣ 第二个测试：事件聚合值匹配当前状态
  //   ✅ 逻辑步骤：
  // 部署 Counter 合约。
  // 记录部署区块号。
  // 循环调用 incBy(1) 到 incBy(10)。
  // 查询从部署区块开始所有的 Increment 事件。
  // 计算事件参数的总和。
  // 对比事件总和与合约中当前变量 x 的实际值是否一致。
  it("The sum of the Increment events should match the current value", async function () {
    const counter = await viem.deployContract("Counter");
    const deploymentBlockNumber = await publicClient.getBlockNumber();

    // run a series of increments
    for (let i = 1n; i <= 10n; i++) {
      await counter.write.incBy([i]);
    }

    const events = await publicClient.getContractEvents({
      address: counter.address,
      abi: counter.abi,
      eventName: "Increment",
      fromBlock: deploymentBlockNumber,
      strict: true,
    });

    // check that the aggregated events match the current value
    let total = 0n;
    for (const event of events) {
      total += event.args.by;
    }

    assert.equal(total, await counter.read.x());
  });
});
