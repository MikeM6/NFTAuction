// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Auction} from "../Auction.sol";

interface IERC721MinimalFT {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IAuctionLikeInitT {
    function initialize(
        address seller_,
        address nft_,
        uint256 tokenId_,
        address currency_,
        uint256 startingPrice_,
        uint64 endTime_
    ) external;
}

interface IAuctionEndedT {
    function ended() external view returns (bool);
}

/// @notice Transparent-proxy compatible factory (no UUPS hooks inside).
contract AuctionFactoryTransparent is Initializable, OwnableUpgradeable {
    event AuctionCreated(
        address indexed auction,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        address currency,
        uint256 startingPrice,
        uint64 endTime
    );

    mapping(address => mapping(uint256 => address)) public getAuction;
    address[] public allAuctions;

    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    function allAuctionsLength() external view returns (uint256) {
        return allAuctions.length;
    }

    /// @notice Clears the recorded auction for an NFT if that auction has ended.
    function clearIfEnded(address nft, uint256 tokenId) external {
        address existing = getAuction[nft][tokenId];
        require(existing != address(0), "no auction");
        require(IAuctionEndedT(existing).ended(), "not ended");
        getAuction[nft][tokenId] = address(0);
    }

    /// @notice Create a new Auction for the given NFT/tokenId. Allows relisting after end.
    function createAuction(
        address nft,
        uint256 tokenId,
        address currency, // 0 for ETH
        uint256 startingPrice,
        uint64 duration
    ) external returns (address auction) {
        address existing = getAuction[nft][tokenId];
        if (existing != address(0)) {
            require(IAuctionEndedT(existing).ended(), "exists");
            getAuction[nft][tokenId] = address(0);
        }
        require(duration > 0, "duration");
        require(
            IERC721MinimalFT(nft).ownerOf(tokenId) == msg.sender,
            "not owner"
        );

        uint64 endTime = uint64(block.timestamp) + duration;
        Auction a = new Auction(
            msg.sender,
            nft,
            tokenId,
            currency,
            startingPrice,
            endTime
        );
        auction = address(a);

        IERC721MinimalFT(nft).safeTransferFrom(msg.sender, auction, tokenId);

        getAuction[nft][tokenId] = auction;
        allAuctions.push(auction);
        emit AuctionCreated(
            auction,
            msg.sender,
            nft,
            tokenId,
            currency,
            startingPrice,
            endTime
        );
    }

    function version() external pure returns (string memory) {
        return "AuctionFactoryTransparent_v2";
    }
}
