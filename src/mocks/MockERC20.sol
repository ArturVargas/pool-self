// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockERC20
 * @notice A simple ERC20 token implementation for testing purposes
 * @dev This contract implements the ERC20 standard with additional mint/burn functions for testing
 */
contract MockERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /**
     * @notice Creates a new MockERC20 token
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _decimals The number of decimals (typically 18)
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /**
     * @notice Approve a spender to transfer tokens on behalf of the caller
     * @param spender The address to approve
     * @param amount The amount to approve
     * @return success Whether the approval was successful
     */
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /**
     * @notice Transfer tokens to a recipient
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /**
     * @notice Transfer tokens from one address to another using allowance
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals

        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /**
     * @notice Mint new tokens to an address (for testing purposes)
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burn tokens from an address (for testing purposes)
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance will never be larger than the total supply
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    /**
     * @notice Mint new tokens to multiple addresses (for testing purposes)
     * @param recipients Array of addresses to mint tokens to
     * @param amounts Array of amounts to mint (same length as recipients)
     */
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) public virtual {
        require(recipients.length == amounts.length, "MockERC20: arrays length mismatch");

        uint256 totalMinted = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            uint256 amount = amounts[i];
            totalMinted += amount;

            // Cannot overflow because the sum of all user balances can't exceed the max uint256 value
            unchecked {
                balanceOf[recipients[i]] += amount;
            }

            emit Transfer(address(0), recipients[i], amount);

            unchecked {
                ++i;
            }
        }

        // Cannot overflow because totalMinted is sum of amounts which are all uint256
        unchecked {
            totalSupply += totalMinted;
        }
    }
}

