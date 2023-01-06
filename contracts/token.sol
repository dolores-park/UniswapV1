// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Your token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'BNN';                 // TODO: Give your token a symbol (all caps!)
    string private constant _name = 'banana';                   // TODO: Give your token a name
            
    constructor() ERC20(_name, _symbol) {}

    bool able_to_mint = true; // TODO: check if any type needed

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    // Function _mint: Create more of your tokens.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function mint(uint amount) 
        public 
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        require (able_to_mint == true, "Mint has been disabled.");
        require (amount > 0, "Must mint non-zero number of tokens.");
        _mint(msg.sender, amount);
    }

    // Function _disable_mint: Disable future minting of your token.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function disable_mint()
        public
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        require (able_to_mint == true, "Mint is already disabled.");
        able_to_mint = false;
    }
}