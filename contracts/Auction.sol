// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ERC20 can mint token
interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// ERC721 can mint token vs NFT
interface IERC721Minimal {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

// Let this contract can receive ERC721
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract Auction is IERC721Receiver {
    address public immutable seller;
    //
    address public immutable nft;
    // auction token now.
    uint256 public immutable tokenId;
    address public immutable currency; // address(0) for ETH
    uint256 public immutable startingPrice;
    uint64 public immutable endTime;

    bool public ended;
    bool private receivedNft;

    address public highestBidder;
    uint256 public highestBid;

    bool private locked;

    event BidPlaced(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);

    // sync look
    modifier nonReentrant() {
        require(!locked, "REENTRANCY");
        locked = true;
        _;
        locked = false;
    }

    // initial base data
    constructor(
        address seller_,
        address nft_,
        uint256 tokenId_,
        address currency_,
        uint256 startingPrice_,
        uint64 endTime_
    ) {
        require(seller_ != address(0), "seller");
        require(nft_ != address(0), "nft");
        require(endTime_ > block.timestamp, "endTime");
        seller = seller_;
        nft = nft_;
        tokenId = tokenId_;
        currency = currency_;
        startingPrice = startingPrice_;
        endTime = endTime_;
    }

    // ERC-721 标准中的安全转移回调函数。
    // 当一个 NFT（ERC721 代币）被安全地转入本合约时，
    // ERC-721 合约会自动调用这个回调函数，用来确认 “接收方是否愿意接收这个 NFT”。
    // 👉 如果返回的结果正确（即标准指定的 selector），NFT 转账才会成功。
    // 没有实现这个函数的合约无法安全接收 NFT。
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        // ✅ 校验调用者必须是指定的 NFT 合约。否则别人可以恶意调用这个函数假装“发 NFT”，导致逻辑错乱。
        require(msg.sender == nft, "not nft");
        // ✅ 确保收到的 NFT 是预期要拍卖的那一个（tokenId 必须匹配）。防止卖家误发其他 NFT。
        require(_tokenId == tokenId, "wrong tokenId");
        // ✅ 防止重复接收。一个拍卖合约只对应一件 NFT。
        require(!receivedNft, "already received");
        // ✅ 标记“已收到 NFT”，只有在真正接收时设置。
        receivedNft = true;
        // ✅ 标准返回值，告诉 ERC-721 合约“我已正确处理该 NFT”。
        return this.onERC721Received.selector;
    }

    // 这个函数允许用户在拍卖期间用 ETH 进行出价。
    // 逻辑是：检查条件 → 退还上个竞拍者 → 记录新的最高价 → 触发事件。
    function bid() external payable nonReentrant {
        // ✅ 表示该拍卖必须是 ETH 模式的（即不是 ERC20 模式）。若是 ERC20 模式，则应使用 bidERC20()。
        require(currency == address(0), "currency != ETH");
        // ✅ 检查拍卖是否仍在进行中。当前区块时间必须小于拍卖结束时间。
        require(block.timestamp < endTime, "ended time");
        uint256 amount = msg.value;
        require(amount >= startingPrice && amount > highestBid, "low bid");

        // refund previous highest
        if (highestBidder != address(0)) {
            (bool ok, ) = payable(highestBidder).call{value: highestBid}("");
            require(ok, "refund failed");
        }

        highestBid = amount;
        highestBidder = msg.sender;
        emit BidPlaced(msg.sender, amount);
    }

    function bidERC20(uint256 amount) external nonReentrant {
        require(currency != address(0), "currency == ETH");
        require(block.timestamp < endTime, "ended time");
        require(amount >= startingPrice && amount > highestBid, "low bid");

        // pull funds from bidder
        require(
            IERC20Minimal(currency).transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "pull fail"
        );

        // refund previous highest
        if (highestBidder != address(0)) {
            require(
                IERC20Minimal(currency).transfer(highestBidder, highestBid),
                "refund fail"
            );
        }

        highestBid = amount;
        highestBidder = msg.sender;
        emit BidPlaced(msg.sender, amount);
    }

    function end() external nonReentrant {
        require(!ended, "already ended");
        require(block.timestamp >= endTime, "not yet");
        ended = true;

        if (highestBidder == address(0)) {
            // no bids, return NFT to seller
            IERC721Minimal(nft).safeTransferFrom(
                address(this),
                seller,
                tokenId
            );
            emit AuctionEnded(address(0), 0);
            return;
        }

        // transfer NFT to winner
        IERC721Minimal(nft).safeTransferFrom(
            address(this),
            highestBidder,
            tokenId
        );

        // pay seller
        if (currency == address(0)) {
            (bool ok, ) = payable(seller).call{value: highestBid}("");
            require(ok, "pay seller fail");
        } else {
            require(
                IERC20Minimal(currency).transfer(seller, highestBid),
                "pay seller fail"
            );
        }

        emit AuctionEnded(highestBidder, highestBid);
    }

    // “如果别人直接往这个拍卖合约打 ETH，而不是通过 bid() 调用，也不要拒绝。”
    //     这样写主要是为了安全和兼容性：

    //      有时退款、退款失败后的 fallback、或外部工具转账 ETH 时，都可能直接发送 ETH；

    //      如果没有 receive()，这种行为会报错；

    //      定义后即使没逻辑，ETH 也能安全进入合约。
    receive() external payable {}
}
