// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC20MinimalT {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20MetadataMinimalT { function decimals() external view returns (uint8); }

interface IERC721MinimalT {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC721ReceiverT {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface AggregatorV3InterfaceT {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

// Transparent-proxy compatible (no UUPS hooks inside)
contract AuctionTransparent is Initializable, OwnableUpgradeable, IERC721ReceiverT {
    address public seller;
    address public nft;
    uint256 public tokenId;
    address public currency;
    uint256 public startingPrice;
    uint64 public endTime;

    address public ethUsdFeed;
    address public tokenUsdFeed;

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

    function initialize(
        address seller_,
        address nft_,
        uint256 tokenId_,
        address currency_,
        uint256 startingPrice_,
        uint64 endTime_
    ) public initializer {
        require(seller_ != address(0), "seller");
        require(nft_ != address(0), "nft");
        require(endTime_ > block.timestamp, "endTime");
        __Ownable_init(seller_);
        seller = seller_;
        nft = nft_;
        tokenId = tokenId_;
        currency = currency_;
        startingPrice = startingPrice_;
        endTime = endTime_;
        // seller is the initial owner (upgrade admin via ProxyAdmin for transparent)
    }

    function setPriceFeeds(address ethUsdFeed_, address tokenUsdFeed_) external onlySeller {
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
        require(IERC20MinimalT(currency).transferFrom(msg.sender, address(this), amount), "pull fail");
        if (highestBidder != address(0)) {
            require(IERC20MinimalT(currency).transfer(highestBidder, highestBid), "refund fail");
        }
        highestBid = amount;
        highestBidder = msg.sender;
        emit BidPlaced(msg.sender, amount);
    }

    function bidERC20For(address beneficiary, uint256 amount) external nonReentrant {
        require(currency != address(0), "currency == ETH");
        require(beneficiary != address(0), "beneficiary");
        require(block.timestamp < endTime, "ended time");
        require(amount >= startingPrice && amount > highestBid, "low bid");
        require(IERC20MinimalT(currency).transferFrom(msg.sender, address(this), amount), "pull fail");
        if (highestBidder != address(0)) {
            require(IERC20MinimalT(currency).transfer(highestBidder, highestBid), "refund fail");
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
            IERC721MinimalT(nft).safeTransferFrom(address(this), seller, tokenId);
            emit AuctionEnded(address(0), 0);
            return;
        }
        IERC721MinimalT(nft).safeTransferFrom(address(this), highestBidder, tokenId);
        if (currency == address(0)) {
            (bool ok, ) = payable(seller).call{value: highestBid}("");
            require(ok, "pay seller fail");
        } else {
            require(IERC20MinimalT(currency).transfer(seller, highestBid), "pay seller fail");
        }
        emit AuctionEnded(highestBidder, highestBid);
    }

    function amountInUsd(uint256 amount) external view returns (uint256, uint8) {
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

    function _priceAndDecimalsForCurrency() internal view returns (uint256, uint8) {
        address feed = currency == address(0) ? ethUsdFeed : tokenUsdFeed;
        require(feed != address(0), "feed not set");
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3InterfaceT(feed).latestRoundData();
        require(answer > 0, "invalid price");
        require(updatedAt > 0, "stale");
        uint8 d = AggregatorV3InterfaceT(feed).decimals();
        return (uint256(answer), d);
    }

    function _currencyDecimals() internal view returns (uint8) {
        if (currency == address(0)) return 18;
        return IERC20MetadataMinimalT(currency).decimals();
    }

    receive() external payable {}
}
