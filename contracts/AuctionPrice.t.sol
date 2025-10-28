// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {MyNFT} from "./MyNFT.sol";
import {TestERC20} from "./TestERC20.sol";
import {AuctionFactory} from "./AuctionFactory.sol";
import {Auction} from "./Auction.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

contract AuctionPriceTest is Test {
    MyNFT nft;
    TestERC20 erc20;
    AuctionFactory factory;

    address seller = address(0xA11CE);
    address alice = address(0xBEEF);

    function setUp() public {
        nft = new MyNFT("MyNFT", "MNFT");
        factory = new AuctionFactory();
        // give alice 100 ther
        vm.deal(alice, 100 ether);
    }

    function _createEthAuction(
        uint64 duration
    ) internal returns (Auction auction) {
        vm.prank(seller);
        // seller mint a nft
        uint256 tokenId = nft.mint(seller);
        vm.prank(seller);
        // seller approval auction for sell its nif
        nft.approve(address(factory), tokenId);
        vm.prank(seller);
        // seller create a auciton wieh ethereum
        address a = factory.createAuction(
            address(nft),
            tokenId,
            address(0),
            0,
            duration
        );
        auction = Auction(payable(a));
    }

    function _createErc20Auction(
        uint64 duration
    ) internal returns (Auction auction) {
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);
        erc20 = new TestERC20("TestToken", "TTK");
        vm.prank(seller);
        nft.approve(address(factory), tokenId);
        vm.prank(seller);
        // seller only get token with erc20
        address a = factory.createAuction(
            address(nft),
            tokenId,
            address(erc20),
            0,
            duration
        );
        auction = Auction(payable(a));
    }

    function test_SetPriceFeeds_OnlySeller() public {
        Auction auction = _createEthAuction(60);
        // create mock creator
        MockAggregatorV3 ethUsd = new MockAggregatorV3(8, 2_500 * 1e8);

        // case1: not seller create aggregator
        vm.expectRevert(bytes("not seller"));
        auction.setPriceFeeds(address(ethUsd), address(0));

        // case2: its seller create aggregator
        vm.prank(seller);
        auction.setPriceFeeds(address(ethUsd), address(0));

        (uint256 usd, uint8 dec) = auction.amountInUsd(1 ether);
        assertEq(dec, 8);
        assertEq(usd, 2_500 * 1e8);
    }

    function test_AmountInUsd_ETH() public {
        Auction auction = _createEthAuction(60);
        MockAggregatorV3 ethUsd = new MockAggregatorV3(8, 3_000 * 1e8);

        vm.prank(seller);
        auction.setPriceFeeds(address(ethUsd), address(0));

        uint256 amount = 2 ether;
        (uint256 usd, uint8 dec) = auction.amountInUsd(amount);
        assertEq(dec, 8);
        assertEq(usd, 6_000 * 1e8);
    }

    function test_CurrentHighestBidInUsd_ETH() public {
        Auction auction = _createEthAuction(60);
        MockAggregatorV3 ethUsd = new MockAggregatorV3(8, 2_000 * 1e8);
        vm.prank(seller);
        auction.setPriceFeeds(address(ethUsd), address(0));

        vm.prank(alice);
        auction.bid{value: 1.5 ether}();

        (uint256 usd, uint8 dec) = auction.currentHighestBidInUsd();
        assertEq(dec, 8);
        assertEq(usd, 3_000 * 1e8);
    }

    function test_AmountInUsd_ERC20() public {
        Auction auction = _createErc20Auction(60);
        MockAggregatorV3 tokenUsd = new MockAggregatorV3(
            8,
            int256(225_000_000)
        );
        vm.prank(seller);
        auction.setPriceFeeds(address(0), address(tokenUsd));

        uint256 amount = 100 ether;
        (uint256 usd, uint8 dec) = auction.amountInUsd(amount);
        assertEq(dec, 8);
        assertEq(usd, 225_000_00000);
    }

    function test_Revert_WhenFeedNotSet() public {
        Auction auction = _createEthAuction(60);
        vm.expectRevert(bytes("feed not set"));
        auction.amountInUsd(1 ether);
    }

    function test_Revert_CurrentHighestBidInUsd_NoBid() public {
        Auction auction = _createEthAuction(60);
        MockAggregatorV3 ethUsd = new MockAggregatorV3(8, 2_000 * 1e8);
        vm.prank(seller);
        auction.setPriceFeeds(address(ethUsd), address(0));

        vm.expectRevert(bytes("no bid"));
        auction.currentHighestBidInUsd();
    }
}
