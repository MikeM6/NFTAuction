// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ERC1967ProxyDeployer is ERC1967Proxy {
    constructor(address implementation, bytes memory data)
        ERC1967Proxy(implementation, data)
    {}
}

contract TransparentUpgradeableProxyDeployer is TransparentUpgradeableProxy {
    constructor(address implementation, address admin, bytes memory data)
        TransparentUpgradeableProxy(implementation, admin, data)
    {}
}

contract ProxyAdminDeployer is ProxyAdmin {
    constructor(address initialOwner) ProxyAdmin(initialOwner) {}
}
