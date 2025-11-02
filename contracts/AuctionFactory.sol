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
        // 针对tokenID为1的，该nft合约的拍卖已被创建了
        require(getAuction[nft][tokenId] == address(0), "exists");
        require(duration > 0, "duration");
        // 这个token是否是这个合约所有的？
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
        // safeTransferFrom(msg.sender, auction, tokenId)，即“从 msg.sender（卖家）转给 auction（拍卖合约地址）指定的 tokenId”。
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
