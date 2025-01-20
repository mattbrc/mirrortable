// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev A simple mock ERC20 token for testing.
 *      By default you can call `mint(...)` as the deployer to give addresses test tokens.
 */
contract MockERC20 is ERC20 {
    address public admin;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        admin = msg.sender;
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == admin, "Only admin can mint");
        _mint(_to, _amount);
    }
}
