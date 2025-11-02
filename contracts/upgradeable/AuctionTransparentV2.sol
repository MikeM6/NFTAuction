// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuctionTransparent} from "./AuctionTransparent.sol";

contract AuctionTransparentV2 is AuctionTransparent {
    function version() external pure returns (uint256) {
        return 2;
    }
}

