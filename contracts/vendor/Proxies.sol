// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// This file exists to ensure Hardhat compiles and generates artifacts for
// OpenZeppelin proxy contracts so scripts can deploy them via viem.

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

