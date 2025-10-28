// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC721MinimalF {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IAuctionLikeInit {
    function initialize(
        address seller_,
        address nft_,
        uint256 tokenId_,
        address currency_,
        uint256 startingPrice_,
        uint64 endTime_
    ) external;
}

/// @notice Upgradeable factory (UUPS) that can create plain Auction or upgradeable Auctions via scripts.
contract AuctionFactoryUUPS is Initializable, UUPSUpgradeable, OwnableUpgradeable {
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
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function allAuctionsLength() external view returns (uint256) {
        return allAuctions.length;
    }

    // Note: In upgradeable setups, creating auctions behind proxies is best handled off-chain
    // using deployment scripts (ProxyAdmin, upgrades plugin). This upgradeable factory keeps
    // storage and events upgradeable, and can be extended in future upgrades.
}
