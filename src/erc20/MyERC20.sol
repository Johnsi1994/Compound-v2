// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.21;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MyERC20 is ERC20 {

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _supply
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _supply);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}