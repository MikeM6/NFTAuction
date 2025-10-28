// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {MyNFT} from "./MyNFT.sol";
import {TestERC20} from "./TestERC20.sol";

// Upgradeable targets
import {AuctionUUPS} from "./upgradeable/AuctionUUPS.sol";
import {AuctionTransparent} from "./upgradeable/AuctionTransparent.sol";

// Proxies (OpenZeppelin)
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract AuctionUUPSV2 is AuctionUUPS {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract AuctionTransparentV2 is AuctionTransparent {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract UpgradeableAuctionTest is Test {
    MyNFT nft;
    TestERC20 erc20;

    address seller = address(0xA11CE);
    address bidder1 = address(0xBEEF);
    address bidder2 = address(0xCAFE);
    address admin = address(0xAD000); // transparent proxy admin

    function setUp() public {
        nft = new MyNFT("MyNFT", "MNFT");
        erc20 = new TestERC20("TestToken", "TTK");
        erc20.mint(bidder1, 10_000 ether);
        erc20.mint(bidder2, 10_000 ether);
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);
    }

    function _mintAndApproveNFT(uint256 tokenId) internal {
        vm.prank(seller);
        nft.mint(seller);
        vm.prank(seller);
        nft.approve(address(this), tokenId);
    }

    function test_UUPS_Proxy_EndToEnd_And_Upgrade() public {
        // Setup NFT
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);

        // Deploy impl and proxy with initializer
        AuctionUUPS impl = new AuctionUUPS();
        uint64 duration = 5;
        uint64 endTime = uint64(block.timestamp) + duration;

        bytes memory initData = abi.encodeWithSelector(
            AuctionUUPS.initialize.selector,
            seller,
            address(nft),
            tokenId,
            address(0), // ETH auction
            0.001 ether,
            endTime
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        AuctionUUPS auction = AuctionUUPS(payable(address(proxy)));

        // Transfer NFT into auction
        vm.prank(seller);
        nft.safeTransferFrom(seller, address(auction), tokenId);

        // Bid flow through proxy
        vm.prank(bidder1);
        auction.bid{value: 0.001 ether}();
        vm.prank(bidder2);
        auction.bid{value: 0.001 ether + 1}();

        // Advance and end
        vm.warp(block.timestamp + duration + 1);
        uint256 sellerBefore = seller.balance;
        auction.end();
        assertEq(nft.ownerOf(tokenId), bidder2);
        assertEq(seller.balance, sellerBefore + (0.001 ether + 1));

        // Upgrade to V2 via UUPS (owner is seller)
        AuctionUUPSV2 v2 = new AuctionUUPSV2();
        vm.prank(seller);
        auction.upgradeToAndCall(address(v2), "");

        // Call new function from V2 through proxy
        uint256 ver = AuctionUUPSV2(payable(address(auction))).version();
        assertEq(ver, 2);

        // State should remain intact
        assertEq(AuctionUUPS(payable(address(auction))).nft(), address(nft));
        assertEq(AuctionUUPS(payable(address(auction))).tokenId(), tokenId);
    }

    function test_Transparent_Proxy_EndToEnd_And_Upgrade() public {
        // Setup NFT
        vm.prank(seller);
        uint256 tokenId = nft.mint(seller);

        // Deploy impl + proxy (OZ v5: proxy constructs its own ProxyAdmin with `initialOwner`)
        AuctionTransparent impl = new AuctionTransparent();
        uint64 duration = 5;
        uint64 endTime = uint64(block.timestamp) + duration;
        bytes memory initData = abi.encodeWithSelector(
            AuctionTransparent.initialize.selector,
            seller,
            address(nft),
            tokenId,
            address(erc20), // ERC20 auction
            100 ether,
            endTime
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), admin, initData);
        AuctionTransparent auction = AuctionTransparent(payable(address(proxy)));

        // Transfer NFT into auction
        vm.prank(seller);
        nft.safeTransferFrom(seller, address(auction), tokenId);

        // bidders approve auction to pull ERC20 funds
        vm.prank(bidder1);
        erc20.approve(address(auction), 100 ether);
        vm.prank(bidder2);
        erc20.approve(address(auction), 101 ether);

        // Place bids via non-admin accounts (transparent admin cannot call logic)
        vm.prank(bidder1);
        auction.bidERC20(100 ether);
        vm.prank(bidder2);
        auction.bidERC20(101 ether);

        // End auction
        vm.warp(block.timestamp + duration + 1);
        uint256 sellerBefore = erc20.balanceOf(seller);
        auction.end();
        assertEq(nft.ownerOf(tokenId), bidder2);
        assertEq(erc20.balanceOf(seller) - sellerBefore, 101 ether);

        // Upgrade via ProxyAdmin
        AuctionTransparentV2 v2 = new AuctionTransparentV2();
        // Resolve ProxyAdmin address from EIP-1967 admin slot
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 raw = vm.load(address(proxy), ADMIN_SLOT);
        address proxyAdminAddr = address(uint160(uint256(raw)));
        ProxyAdmin pa = ProxyAdmin(proxyAdminAddr);
        vm.prank(admin);
        pa.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(v2), "");

        // Call new function via non-admin address
        uint256 ver = AuctionTransparentV2(payable(address(auction))).version();
        assertEq(ver, 2);
        // State unchanged
        assertEq(AuctionTransparent(payable(address(auction))).nft(), address(nft));
        assertEq(AuctionTransparent(payable(address(auction))).tokenId(), tokenId);
    }
}
