// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC20MinimalUp {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC20MetadataMinimalUp {
    function decimals() external view returns (uint8);
}

interface IERC721MinimalUp {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface IERC721ReceiverUp {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface AggregatorV3InterfaceUp {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract AuctionUUPS is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IERC721ReceiverUp
{
    // Storage (no immutables in upgradeable contracts)
    address public seller;
    address public nft;
    uint256 public tokenId;
    address public currency; // address(0) for ETH
    uint256 public startingPrice;
    uint64 public endTime;

    address public ethUsdFeed; // optional
    address public tokenUsdFeed; // optional

    bool public ended;
    bool private receivedNft;

    address public highestBidder;
    uint256 public highestBid;

    bool private locked;

    event BidPlaced(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);
    event PriceFeedsUpdated(address ethUsdFeed, address tokenUsdFeed);

    modifier nonReentrant() {
        require(!locked, "REENTRANCY");
        locked = true;
        _;
        locked = false;
    }

    modifier onlySeller() {
        require(msg.sender == seller, "not seller");
        _;
    }

    // 可升级拍卖合约（AuctionUUPS） 的“构造函数替代品”
    function initialize(
        address seller_,
        address nft_,
        uint256 tokenId_,
        address currency_,
        uint256 startingPrice_,
        uint64 endTime_
    ) public initializer {
        // 禁止空地址（防止逻辑错误或潜在攻击）。
        // 确保结束时间合理（不能立刻结束）。
        require(seller_ != address(0), "seller");
        require(nft_ != address(0), "nft");
        require(endTime_ > block.timestamp, "endTime");

        // 初始化 OwnableUpgradeable 合约，设置 owner 为卖家。
        // 这意味着最初的 owner == seller，因此卖家一开始也掌握升级权限。
        __Ownable_init(seller_);
        // 初始化 UUPSUpgradeable 组件（设置版本号、存储槽等底层内容）。
        __UUPSUpgradeable_init();

        seller = seller_;
        nft = nft_;
        tokenId = tokenId_;
        currency = currency_;
        startingPrice = startingPrice_;
        endTime = endTime_;

        // seller is the initial upgrade owner
    }

    // UUPS auth: only owner can upgrade
    // 当有人尝试升级合约（通常通过代理的接口）时，会调用：
    // upgradeTo(address newImplementation)
    // 在 UUPSUpgradeable 内部，这个函数会触发：
    // _authorizeUpgrade(newImplementation);
    //于是执行你定义的 _authorizeUpgrade()。

    //      如果调用者 不是 owner → onlyOwner 抛错。

    //      如果调用者是 owner → 允许升级逻辑地址。
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setPriceFeeds(
        address ethUsdFeed_,
        address tokenUsdFeed_
    ) external onlySeller {
        ethUsdFeed = ethUsdFeed_;
        tokenUsdFeed = tokenUsdFeed_;
        emit PriceFeedsUpdated(ethUsdFeed_, tokenUsdFeed_);
    }

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == nft, "not nft");
        require(_tokenId == tokenId, "wrong tokenId");
        require(!receivedNft, "already received");
        receivedNft = true;
        return this.onERC721Received.selector;
    }

    function bid() external payable nonReentrant {
        require(currency == address(0), "currency != ETH");
        require(block.timestamp < endTime, "ended time");
        uint256 amount = msg.value;
        require(amount >= startingPrice && amount > highestBid, "low bid");
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
        require(
            IERC20MinimalUp(currency).transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "pull fail"
        );
        if (highestBidder != address(0)) {
            require(
                IERC20MinimalUp(currency).transfer(highestBidder, highestBid),
                "refund fail"
            );
        }
        highestBid = amount;
        highestBidder = msg.sender;
        emit BidPlaced(msg.sender, amount);
    }

    function bidERC20For(
        address beneficiary,
        uint256 amount
    ) external nonReentrant {
        require(currency != address(0), "currency == ETH");
        require(beneficiary != address(0), "beneficiary");
        require(block.timestamp < endTime, "ended time");
        require(amount >= startingPrice && amount > highestBid, "low bid");
        require(
            IERC20MinimalUp(currency).transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "pull fail"
        );
        if (highestBidder != address(0)) {
            require(
                IERC20MinimalUp(currency).transfer(highestBidder, highestBid),
                "refund fail"
            );
        }
        highestBid = amount;
        highestBidder = beneficiary;
        emit BidPlaced(beneficiary, amount);
    }

    function end() external nonReentrant {
        require(!ended, "already ended");
        require(block.timestamp >= endTime, "not yet");
        ended = true;

        if (highestBidder == address(0)) {
            IERC721MinimalUp(nft).safeTransferFrom(
                address(this),
                seller,
                tokenId
            );
            emit AuctionEnded(address(0), 0);
            return;
        }
        IERC721MinimalUp(nft).safeTransferFrom(
            address(this),
            highestBidder,
            tokenId
        );
        if (currency == address(0)) {
            (bool ok, ) = payable(seller).call{value: highestBid}("");
            require(ok, "pay seller fail");
        } else {
            require(
                IERC20MinimalUp(currency).transfer(seller, highestBid),
                "pay seller fail"
            );
        }
        emit AuctionEnded(highestBidder, highestBid);
    }

    function amountInUsd(
        uint256 amount
    ) external view returns (uint256, uint8) {
        (uint256 price, uint8 usdDec) = _priceAndDecimalsForCurrency();
        uint8 curDec = _currencyDecimals();
        require(price > 0, "price");
        uint256 scaled = amount * price;
        uint256 usdAmount = scaled / (10 ** curDec);
        return (usdAmount, usdDec);
    }

    function currentHighestBidInUsd() external view returns (uint256, uint8) {
        require(highestBid > 0, "no bid");
        return this.amountInUsd(highestBid);
    }

    function _priceAndDecimalsForCurrency()
        internal
        view
        returns (uint256, uint8)
    {
        address feed = currency == address(0) ? ethUsdFeed : tokenUsdFeed;
        require(feed != address(0), "feed not set");
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3InterfaceUp(feed)
            .latestRoundData();
        require(answer > 0, "invalid price");
        require(updatedAt > 0, "stale");
        uint8 d = AggregatorV3InterfaceUp(feed).decimals();
        return (uint256(answer), d);
    }

    function _currencyDecimals() internal view returns (uint8) {
        if (currency == address(0)) return 18;
        return IERC20MetadataMinimalUp(currency).decimals();
    }

    receive() external payable {}
}
