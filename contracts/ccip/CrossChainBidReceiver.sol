// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
// Minimal ERC20 interface
interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}
// Minimal Auction interface (bidERC20 only)
interface IAuctionERC20Bid {
    function currency() external view returns (address);
    function bidERC20(uint256 amount) external;
    function bidERC20For(address beneficiary, uint256 amount) external;
}
// ----------------- Chainlink CCIP minimal types -----------------
library Client {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }
    struct Any2EVMMessage {
        bytes32 messageId; // unique ID for the message
        uint64 sourceChainSelector; // source chain ID
        bytes sender; // abi-encoded address of sender on source chain
        bytes data; // arbitrary data payload
        EVMTokenAmount[] destTokenAmounts; // tokens delivered with the message to this chain
    }
}
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}
/// @title CrossChainBidReceiver
/// @notice CCIP receiver that accepts bridged ERC20 funds + a bidding instruction,
///         then places an ERC20 bid into an existing Auction on this chain.
/// @dev Limitations (MVP):
///  - Only supports ERC20 auctions (Auction.currency() != address(0)).
///  - Refunds/winnings are local to the destination chain recipient.
///  - The bridged token must exactly match the Auction.currency().
contract CrossChainBidReceiver is IAny2EVMMessageReceiver {
    address public immutable router; // CCIP router expected caller of ccipReceive
    address public owner; // admin for allowlist mgmt and recoveries
    // Optional allowlist: chainSelector => sourceSender(bytes) => allowed
    mapping(uint64 => mapping(bytes => bool)) public allowedSender;
    event AllowedSenderSet(
        uint64 indexed chainSelector,
        bytes indexed sender,
        bool allowed
    );
    event CrossChainBidExecuted(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed auction,
        address token,
        uint256 amount,
        address localRecipient
    );
    error NotRouter();
    error NotOwner();
    error SenderNotAllowed();
    error NoTokenBridged();
    error TokenMismatch();
    error AmountMismatch();
    error UnsupportedAuctionCurrency();
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    // 绑定 Chainlink CCIP Router 地址；
    // 设置管理员（owner）为部署者本人。
    // 只有这个 owner 才能修改配置、找回资金、或者转移管理员。
    constructor(address router_) {
        require(router_ != address(0), "router");
        router = router_;
        owner = msg.sender;
    }
    // 允许当前管理员（owner）安全地转移管理员权限给别人。
    // 这是标准的“所有权转移函数”模式，类似于 OpenZeppelin 的 Ownable.transferOwnership()。
    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "owner");
        owner = newOwner;
    }

    // sourceChainSelector — 来源链的编号（Chainlink 的专用 selector，不是 chainId）
    // sender — 源链上发送消息的合约地址（经过 ABI 编码成 bytes）
    // 这两个要素共同决定了“消息从哪条链、哪个合约发出”。
    // 让管理员（owner）手动指定哪些 “(源链, 发送者)” 被允许发消息给本合约。
    function setAllowedSender(
        uint64 chainSelector,
        bytes calldata sender,
        bool allowed
    ) external onlyOwner {
        allowedSender[chainSelector][sender] = allowed;
        emit AllowedSenderSet(chainSelector, sender, allowed);
    }

    /// @dev Message data format: abi.encode(auction,address(token),uint256(amount),address(localRecipient))
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external override {
        // 只允许 CCIP Router 投递，阻断任意账户的伪造调用。
        if (msg.sender != router) revert NotRouter();

        // 白名单校验（源链 + 源地址）
        if (!allowedSender[message.sourceChainSelector][message.sender])
            revert SenderNotAllowed();

        // 解码消息体
        (
            address auctionAddr,
            address token,
            uint256 amount,
            address localRecipient
        ) = abi.decode(message.data, (address, address, uint256, address));

        // 是否带币？
        if (message.destTokenAmounts.length == 0) revert NoTokenBridged();

        // 桥过来的第一个 token 与负载声明一致：
        Client.EVMTokenAmount memory t = message.destTokenAmounts[0];
        if (t.token != token) revert TokenMismatch();
        if (t.amount != amount) revert AmountMismatch();

        // 获取拍卖
        IAuctionERC20Bid auction = IAuctionERC20Bid(auctionAddr);

        // 拍卖币种与声明一致且为 ERC20：
        address auctionCurrency = auction.currency();
        if (auctionCurrency == address(0)) revert UnsupportedAuctionCurrency();
        if (auctionCurrency != token) revert TokenMismatch();

        // 授权：允许拍卖合约从本接收器把刚桥来的 token 拉走
        require(IERC20Like(token).approve(auctionAddr, amount), "approve");
        // 代表本地受益人出价：
        auction.bidERC20For(localRecipient, amount);
        emit CrossChainBidExecuted(
            message.messageId,
            message.sourceChainSelector,
            auctionAddr,
            token,
            amount,
            localRecipient
        );
    }
    // Owner escape hatch to recover stray tokens sent here by mistake
    function recoverERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(IERC20Like(token).transfer(to, amount), "recover fail");
    }
}
