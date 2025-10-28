// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {MyNFT} from "./MyNFT.sol";
import {TestERC20} from "./TestERC20.sol";
import {AuctionFactory} from "./AuctionFactory.sol";
import {Auction} from "./Auction.sol";
import {CrossChainBidReceiver, Client} from "./ccip/CrossChainBidReceiver.sol";

contract CrossChainAuctionCCIPTest is Test {
    MyNFT nft;
    TestERC20 erc20;
    AuctionFactory factory;

    address seller = address(0xA11CE);
    address localRecipient = address(0xBEEF);
    address router = address(0xCAFE); // simulate CCIP router caller

    function setUp() public {
        nft = new MyNFT("MyNFT", "MNFT");
        factory = new AuctionFactory();
    }

    function test_CrossChain_ERC20_Bid_via_ccipReceive() public {
        // mint NFT to seller and create ERC20 auction
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);

        erc20 = new TestERC20("TestToken", "TTK");

        vm.prank(seller);
        nft.approve(address(factory), tokenId);

        uint256 startingPrice = 100 ether;
        uint64 duration = 120;
        vm.prank(seller);
        address auctionAddr = factory.createAuction(
            address(nft),
            tokenId,
            address(erc20),
            startingPrice,
            duration
        );
        Auction auction = Auction(payable(auctionAddr));

        // deploy CCIP receiver with expected router address
        CrossChainBidReceiver receiver = new CrossChainBidReceiver(router);

        // allow a source sender on a chain selector
        uint64 selector = uint64(16015286601757825753); // example
        bytes memory sourceSender = abi.encode(address(0x1234));
        receiver.setAllowedSender(selector, sourceSender, true);

        // pre-fund receiver with the bridged token to simulate CCIP token delivery
        uint256 bridgedAmount = startingPrice + 50;
        erc20.mint(address(receiver), bridgedAmount);

        // craft CCIP message
        Client.Any2EVMMessage memory m;
        m.messageId = bytes32(uint256(0x11));
        m.sourceChainSelector = selector;
        m.sender = sourceSender;
        m.data = abi.encode(auctionAddr, address(erc20), bridgedAmount, localRecipient);
        m.destTokenAmounts = new Client.EVMTokenAmount[](1);
        m.destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(erc20), amount: bridgedAmount });

        // call ccipReceive from router
        vm.prank(router);
        receiver.ccipReceive(m);

        // assert highest bid and bidder
        assertEq(auction.highestBid(), bridgedAmount);
        assertEq(auction.highestBidder(), localRecipient);
        // funds moved from receiver to auction contract
        assertEq(erc20.balanceOf(address(receiver)), 0);
        assertEq(erc20.balanceOf(address(auction)), bridgedAmount);
    }
}

