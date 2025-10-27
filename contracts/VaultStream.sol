// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VaultStream
 * @dev A simple decentralized vault system where users can deposit and withdraw ETH securely.
 * It maintains a record of all deposits per user.
 */
contract VaultStream {
    // Mapping to store user balances
    mapping(address => uint256) private balances;

    // Event emitted on deposit
    event Deposited(address indexed user, uint256 amount);

    // Event emitted on withdrawal
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @dev Allows a user to deposit ETH into the vault.
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev Allows a user to withdraw a specific amount of their deposited ETH.
     * @param amount The amount to withdraw.
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Withdrawal amount must be greater than zero");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Returns the balance of the calling user.
     * @return The user's balance in wei.
     */
    function getBalance() external view returns (uint256) {
        return balances[msg.sender];
    }
}
