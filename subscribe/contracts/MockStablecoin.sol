// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockStablecoin
 * @notice Simple ERC-20 with a public faucet `mint` for local/testnet development.
 *         Do NOT deploy to production as-is.
 */
contract MockStablecoin is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Faucet mint for testing.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
