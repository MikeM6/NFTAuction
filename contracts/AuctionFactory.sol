// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Auction.sol";

interface IERC721Full is IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract AuctionFactory {
    event AuctionCreated(
        address indexed auction,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        address currency,
        uint256 startingPrice,
        uint64 endTime
    );

    // {NFT -> {NFT's token -> auction}}
    mapping(address => mapping(uint256 => address)) public getAuction;
    address[] public allAuctions;

    function allAuctionsLength() external view returns (uint256) {
        return allAuctions.length;
    }

    function createAuction(
        address nft,
        uint256 tokenId,
        address currency, // 0 for ETH
        uint256 startingPrice,
        uint64 duration
    ) external returns (address auction) {
        require(getAuction[nft][tokenId] == address(0), "exists");
        require(duration > 0, "duration");
        require(IERC721Full(nft).ownerOf(tokenId) == msg.sender, "not owner");

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

        // seller must approve factory for this NFT beforehand
        IERC721Full(nft).safeTransferFrom(msg.sender, auction, tokenId);

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
}
