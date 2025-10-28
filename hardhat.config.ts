// hardhat.config.ts (Hardhat 3+)
import "@nomicfoundation/hardhat-toolbox-viem"; // Hardhat 3 + viem 工具
import hardhatNodeTestRunner from "@nomicfoundation/hardhat-node-test-runner";
import hardhatViem from "@nomicfoundation/hardhat-viem";
import hardhatViemAssertions from "@nomicfoundation/hardhat-viem-assertions";
import { configVariable } from "hardhat/config"; // Hardhat 3 的配置变量

export default {
  plugins: [hardhatViem, hardhatViemAssertions, hardhatNodeTestRunner],
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

  // Hardhat 3 网络配置
  networks: {
    // 内置本地模拟链（无需先起节点）
    dev: {
      type: "edr-simulated",
      chainType: "l1",
      chainId: 31337,
    },

    // 连接到本机已启动的节点（npx hardhat node / Anvil）
    localhost: {
      type: "http",
      chainType: "l1",
      url: "http://127.0.0.1:8545",
      accounts: "remote",
      chainId: 31337,
    },

    // Sepolia 测试网（需要环境变量或 keystore）
    sepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.SEPOLIA_RPC_URL!,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    }, verify: {
      etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY || "",
      },
    },
  },

  paths: {
    sources: "contracts",
    tests: {
      nodejs: "test",
      solidity: "contracts",
    },
    cache: "cache",
    artifacts: "artifacts",
  },

  // Mocha 选项（node:test 语法兼容 Hardhat v3）
  test: {
    mocha: { timeout: 200_000 },
  },
};
