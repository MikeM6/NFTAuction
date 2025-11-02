// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuctionUUPS} from "./AuctionUUPS.sol";

contract AuctionUUPSV2 is AuctionUUPS {
    function version() external pure returns (uint256) {
        return 2;
    }
}

