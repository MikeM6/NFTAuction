// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC721MinimalFT {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
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

    // Note: Creation of proxies is recommended to be handled in deployment scripts (Transparent proxies).
}
