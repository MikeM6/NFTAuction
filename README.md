NFTAuction

基于 Hardhat 3 + viem 的 NFT 拍卖合约与脚本合集，支持：

- 单次拍卖合约（支持 ETH/指定 ERC20 出价，安全退款与收款）
- 工厂创建与管理拍卖
- 可升级版本（UUPS、Transparent 两种模式）
- 可选 Chainlink 价格喂价（USD 估值辅助）
- 跨链 CCIP 出价接收（ERC20 跨链到目标链并代为出价）
- 配套部署、竞拍、结束、铸造等脚本

项目结构

- `contracts/`
  - `Auction.sol`：基础拍卖（非升级），ETH/ERC20 出价、退款、结束；可选 Chainlink 喂价用于 USD 估值。
  - `AuctionFactory.sol`：创建 `Auction` 并将 NFT 安全转入；提供 `getAuction(nft, tokenId)` 与 `allAuctions`。
  - `upgradeable/`
    - `AuctionUUPS.sol`：UUPS 可升级版拍卖（OZ UUPS + OwnableUpgradeable）。
    - `AuctionTransparent.sol`：Transparent 代理兼容的拍卖（无 UUPS 钩子）。
    - `AuctionFactoryUUPS.sol`：UUPS 可升级版工厂，支持结束后重复上架（含 `clearIfEnded`）。
    - `AuctionFactoryTransparent.sol`：Transparent 兼容版工厂。
  - `ccip/CrossChainBidReceiver.sol`：CCIP 接收器，接收跨链 ERC20 并代本地受益人对拍卖 `bidERC20For`。
  - `vendor/Proxies.sol`、`vendor/ProxyWrappers.sol`：引入/包装 OZ 代理（`ERC1967Proxy`、`TransparentUpgradeableProxy`、`ProxyAdmin`）便于脚本部署。
  - `MyNFT.sol`：ERC721 示例，支持 `mint`。`TestERC20.sol`：ERC20 示例，支持 `mint`。
- `scripts/`（Hardhat 3 + viem）
  - 部署：`deploy_factory.ts`、`deploy_mynft.ts`、`deploy_erc20.ts`、`deploy_uups.ts`、`deploy_transparent.ts`
  - 升级：`upgrade_factory_uups.ts`、`upgrade_factory_transparent.ts`
  - 业务：`create_auction.ts`、`bid_eth.ts`、`bid_erc20.ts`、`end_auction.ts`、`mint.ts`、`set_price_feeds.ts`
- 其它
  - `hardhat.config.ts`：Hardhat 3 配置（`dev`/`localhost`/`sepolia` 网络示例，Etherscan 验证配置）
  - `test/`：拍卖与价格逻辑测试

功能说明

- 拍卖（`Auction` / `AuctionUUPS` / `AuctionTransparent`）
  - 出价方式
    - ETH 出价：`bid()`；若有上一位最高出价则自动退款
    - ERC20 出价：`bidERC20(uint256)`；内部 `transferFrom` 拉取，若有上一位最高出价则原路退还
  - 代投：`bidERC20For(address beneficiary, uint256 amount)`（如由跨链接收器发起）
  - 结束：`end()` 到期后任何人可调用；若有人中标则转 NFT 给中标者并向卖家结算，否则退回 NFT
  - 价格喂价（可选）：卖家 `setPriceFeeds(ethUsdFeed, tokenUsdFeed)`；查询 `amountInUsd`、`currentHighestBidInUsd`
- 工厂（`AuctionFactory*`）
  - `createAuction(nft, tokenId, currency, startingPrice, duration)` 创建拍卖
    - 需要调用者当前拥有该 NFT；创建时会 `safeTransferFrom` 将 NFT 转入新拍卖合约
    - 非升级版：同一 `nft+tokenId` 仅允许一个活动拍卖
    - 升级版：允许结束后重新上架（`clearIfEnded` 清理映射再创建）
  - 查询：`getAuction(nft, tokenId)`、`allAuctionsLength()`
- 跨链 CCIP（`CrossChainBidReceiver`）
  - 仅接受 allowlist 中“源链 + 源地址”的 CCIP Router 消息
  - 要求消息附带的 ERC20 与拍卖 `currency()` 完全一致；随后 `approve + bidERC20For(localRecipient, amount)`
  - 管理：`setAllowedSender`、`setOwner`、`recoverERC20`

环境准备

- Node.js 18+、npm 10+
- 安装：`npm i`
- `.env`（可选）
  - `PRIVATE_KEY`：部署账户私钥
  - `SEPOLIA_RPC_URL`：Sepolia RPC
  - `ETHERSCAN_API_KEY`：Etherscan 验证（可选）

编译与测试

- 编译：`npx hardhat compile`
- 测试：`npm test` 或 `npx hardhat test`

部署与使用（示例）

- 命令基于 PowerShell，`--network sepolia` 或 `--network localhost` 视配置而定

1. 部署示例 NFT / ERC20

- 部署 NFT：`npx hardhat run scripts/deploy_mynft.ts --network sepolia`
  - 可选：`--name MyNFT --symbol MNFT` 或设置 `NFT_NAME` / `NFT_SYMBOL`
- 部署 ERC20：`npx hardhat run scripts/deploy_erc20.ts --network sepolia`
  - 可选：`--name TestToken --symbol TT` 或设置 `ERC20_NAME` / `ERC20_SYMBOL`

2. 铸造（可选）

- 示例：
  - `$env:NFT_ADDRESS="0x...";`
  - `$env:ERC20_ADDRESS="0x...";`
  - `$env:MINT_TO="0x...";`
  - `$env:ERC20_MINT_AMOUNT="1000";`
  - `npx hardhat run scripts/mint.ts --network sepolia`

3. 部署工厂

- 非升级版：`npx hardhat run scripts/deploy_factory.ts --network sepolia`
- 可升级（示例脚本，含占位参数，按需修改）
  - UUPS：`npx hardhat run scripts/deploy_uups.ts --network sepolia`
  - Transparent：`npx hardhat run scripts/deploy_transparent.ts --network sepolia`

4. 创建拍卖前准备

- 在钱包或交互工具中授权工厂可转移 NFT（以下任选一）
  - `ERC721.approve(factory, tokenId)`
  - `ERC721.setApprovalForAll(factory, true)`

5. 创建拍卖

- `$env:FACTORY_ADDRESS="0x...";`
- `$env:NFT_ADDRESS="0x...";`
- `$env:TOKEN_ID="1";`
- `# ETH 拍卖省略 CURRENCY_ADDRESS（或填 0x00..00），ERC20 拍卖设置为代币地址`
- `$env:CURRENCY_ADDRESS="0x0000000000000000000000000000000000000000";`
- `$env:STARTING_PRICE_WEI="0";`
- `$env:DURATION_SECONDS="3600";`
- `npx hardhat run scripts/create_auction.ts --network sepolia`

6. 竞价

- ETH：
  - `$env:AUCTION_ADDRESS="0x...";`
  - `$env:BID_ETH="0.05";`
  - `npx hardhat run scripts/bid_eth.ts --network sepolia`
- ERC20：
  - `$env:AUCTION_ADDRESS="0x...";`
  - `$env:ERC20_ADDRESS="0x...";`
  - `$env:BID_AMOUNT="100";`
  - `npx hardhat run scripts/bid_erc20.ts --network sepolia`

7. 结束拍卖

- `$env:AUCTION_ADDRESS="0x...";`
- `npx hardhat run scripts/end_auction.ts --network sepolia`

8. 设置价格喂价（可选）

- `$env:AUCTION_ADDRESS="0x...";`
- `$env:ETH_USD_FEED="0x...";`
- `$env:TOKEN_USD_FEED="0x...";`
- `npx hardhat run scripts/set_price_feeds.ts --network sepolia`

升级流程（可选）

- UUPS 工厂升级：
  - `$env:FACTORY_PROXY="0x...";`
  - `npx hardhat run scripts/upgrade_factory_uups.ts --network sepolia`
  - 部署新实现并对代理 `upgradeTo(newImpl)`，随后读取 `version()` 校验
- Transparent 工厂升级：
  - `$env:PROXY_ADMIN="0x...";`
  - `$env:FACTORY_PROXY="0x...";`
  - `npx hardhat run scripts/upgrade_factory_transparent.ts --network sepolia`
  - 通过 `ProxyAdmin.upgrade(proxy, newImpl)` 执行升级并读取 `version()` 校验

网络配置说明

- `hardhat.config.ts` 已示例：
  - `dev`：内置模拟链（Hardhat v3 EDR）
  - `localhost`：连接本地节点（如 Anvil/Hardhat node）
  - `sepolia`：从 `.env` 读取 `SEPOLIA_RPC_URL` / `PRIVATE_KEY`
  - 验证：`ETHERSCAN_API_KEY`（可选）

常见问题

- 创建拍卖前未授权工厂转移 NFT → 在钱包中对工厂地址 `approve` 或 `setApprovalForAll`
- ERC20 出价失败 → 检查余额、`approve` 数量、拍卖 `currency` 是否与出价代币一致
- USD 估值函数报错 → 需先设置对应 Chainlink 喂价地址
- TestERC20**合约地址**：0x114f73a8857b93fdd16722cce754f6de9ce7c391
- MyNFT**合约地址**：0xfedbe87c42ba210021cedfde2a657885418a7f0a
- AcutionFactory**合约地址**：0x52107ff552c5b44f19dc8e08c6157ca8c7a67e14
- Auction1 合约地址：0x49A389af1C6aAB805AfF9f6d0e690eAC8548297A
- Auction2 合约地址：0xa730B3007945AD0D1279bAD36Ec7433E38786eaE
- Auction3 合约地址：0xc289f946CF5659a8f0073CA4E53Ff17b95592B4d
- MockAggregatorV3 ether 地址：0x1f1fAAc2f0fc637222A2362A610D55923A3081D1
- MockAggregatorV3 erc20 地址：0x0A8FF2ED5Ca50C6d8fe8710e63cA2A041a8a6aC3
- 0 地址：0x0000000000000000000000000000000000000000
- AuctionUUPS 合约地址：0x64b22D5975caAd2a90DFf1cb14FFc63c0Cb945ff
- ERC1967 代理合约地址：0x491907fa821D50c0756af277fA2eEa7313548Fb8
- ERC1967 绑定 AuctionUUPS；
- AuctionUUPS2 合约地址：0x6b853f38411C4dCccB7BE1a810bbEac9fF70D1f5
- AuctionTransparent：0x47780e745e1023f0b0391ED195e373c810D12348
- Transparent：0x7ea47042F9dF795e52002f6c4F2196173ECFC2F5
- admin 是 bidder1：0x11979f452E917d35849894717E6fA38123bD812F
- TransparentV2：0xf895b91D0Ab0C0aA83Ee1467d69E7A0c52143abd
