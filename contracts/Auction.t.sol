// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {MyNFT} from "./MyNFT.sol";
import {TestERC20} from "./TestERC20.sol";
import {AuctionFactory} from "./AuctionFactory.sol";
import {Auction} from "./Auction.sol";

contract AuctionTest is Test {
    MyNFT nft;
    TestERC20 erc20;
    AuctionFactory factory;

    address seller = address(0xA11CE);
    address bidder1 = address(0xBEEF);
    address bidder2 = address(0xCAFE);

    function setUp() public {
        nft = new MyNFT("MyNFT", "MNFT");
        factory = new AuctionFactory();
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);
    }

    function test_ETH_Auction_EndToEnd() public {
        // mint NFT to seller
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);

        // approve and create auction
        vm.prank(seller);
        nft.approve(address(factory), tokenId);
        uint256 startingPrice = 0.001 ether;
        uint64 duration = 5;
        vm.prank(seller);
        address auctionAddr = factory.createAuction(
            address(nft),
            tokenId,
            address(0),
            startingPrice,
            duration
        );
        Auction auction = Auction(payable(auctionAddr));

        // bidder1 bids
        vm.prank(bidder1);
        auction.bid{value: startingPrice}();

        // bidder2 outbids
        vm.prank(bidder2);
        auction.bid{value: startingPrice + 1}();

        // travel to end time and end auction
        uint64 endTime = auction.endTime();
        vm.warp(uint256(endTime) + 1);

        uint256 sellerBefore = seller.balance;
        auction.end();

        // NFT ownership transferred
        assertEq(nft.ownerOf(tokenId), bidder2);

        // Seller received highest bid
        assertEq(seller.balance, sellerBefore + (startingPrice + 1));
    }

    function test_ERC20_Auction_EndToEnd() public {
        // mint NFT to seller
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);

        // deploy ERC20 and mint to bidders
        erc20 = new TestERC20("TestToken", "TTK");
        erc20.mint(bidder1, 10_000 ether);
        erc20.mint(bidder2, 10_000 ether);

        // approve and create auction (ERC20 currency)
        vm.prank(seller);
        nft.approve(address(factory), tokenId);
        uint256 startingPrice = 100 ether;
        uint64 duration = 5;
        vm.prank(seller);
        address auctionAddr = factory.createAuction(
            address(nft),
            tokenId,
            address(erc20),
            startingPrice,
            duration
        );
        Auction auction = Auction(payable(auctionAddr));

        // bidders approve auction to pull funds
        vm.prank(bidder1);
        erc20.approve(auctionAddr, startingPrice);
        vm.prank(bidder2);
        erc20.approve(auctionAddr, startingPrice + 1);

        // bids
        vm.prank(bidder1);
        auction.bidERC20(startingPrice);
        vm.prank(bidder2);
        auction.bidERC20(startingPrice + 1);

        // warp and end
        uint64 endTime = auction.endTime();
        vm.warp(uint256(endTime) + 1);

        uint256 sellerBefore = erc20.balanceOf(seller);
        auction.end();

        // NFT transferred to highest bidder
        assertEq(nft.ownerOf(tokenId), bidder2);
        // Seller received payment
        assertEq(erc20.balanceOf(seller) - sellerBefore, startingPrice + 1);
    }
}
