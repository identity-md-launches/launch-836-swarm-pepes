// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Swarm Pepes (SWARMPEPES)
/// @notice Fixed supply ERC-20 with 18 decimals and exact, fee-free transfers.
/// @dev The constructor caller receives the entire supply, including when it is a factory.
/// There are no externally accessible mint, burn, administrative, or upgrade functions.
contract SwarmPepes is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Swarm Pepes", "SWARMPEPES") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
