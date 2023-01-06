// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


contract TokenExchange is Ownable {
    string public exchange_name = '';

    address tokenAddr = 0xF6733AB90988c457a5Ac360D7f8dfB9E24aA108F;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);
    address feeAddr = 0x0000000000000000000000000000000000000000;                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    uint private token_fee_pool = 0;
    uint private eth_fee_pool = 0;

    mapping(address => uint) private lps; // base 10**10
    mapping(address => uint) private lps_reward_eth;
    mapping(address => uint) private lps_reward_token;
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 5;                // TODO Part 5: Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;
    uint private denominator = 10**10;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;

        k = token_reserves * eth_reserves;

        // fee address for reinvestment
        lp_providers.push(feeAddr);
        lps[feeAddr] = 0;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    function fee_reward_eth(uint amount) private {
        for (uint i = 0; i < lp_providers.length; i++){
            address lp_curr = lp_providers[i];
            lps_reward_eth[lp_curr] += lps[lp_curr] * amount;
        }
    }

    function fee_reward_token(uint amount) private {
        for (uint i = 0; i < lp_providers.length; i++){
            address lp_curr = lp_providers[i];
            lps_reward_token[lp_curr] += lps[lp_curr] * amount;
        }
    }

    function reinvest() private {
        uint amountEth_to_invest = Math.min(eth_fee_pool, token_fee_pool * eth_reserves / token_reserves);
        uint amountToken_to_invest = amountEth_to_invest * token_reserves / eth_reserves; // might be some rounding off error

        eth_fee_pool -= amountEth_to_invest;
        token_fee_pool -= amountToken_to_invest;

        uint prev_eth_reserves = eth_reserves;

        eth_reserves += amountEth_to_invest;
        token_reserves += amountToken_to_invest;
        k = eth_reserves * token_reserves;

        // below basically is adding liquidity (adding eth to feeAddr & update proportions) 
        for (uint i = 0; i < lp_providers.length; i++) {
            address addr = lp_providers[i];
            if (addr == feeAddr){
                lps[feeAddr] = lps[feeAddr] * prev_eth_reserves / eth_reserves + denominator * amountEth_to_invest / eth_reserves;
            } else {
                lps[addr] = lps[addr] * prev_eth_reserves / eth_reserves;
            }
        }
    }

    function priceTokenPerETH()
        public
        view
        returns (uint)
    {
        require(eth_reserves > 0, "Insufficient ETH Liquidity");
        return token_reserves * 10**18 / eth_reserves;
    }

    function isNewLpProvider(address provider_addr) 
        public view returns (bool) 
    {   
        bool is_new = true;
        for (uint i = 0; i < lp_providers.length; i++){
            if (provider_addr == lp_providers[i]){
                is_new = false;
                break;
            }
        }
        return is_new;
    }

    function updateProportions(uint amountETH, bool addLqdFlag)
        internal returns (uint)
    {
        uint senderIdx;
        for (uint i = 0; i < lp_providers.length; i++) {
            address addr = lp_providers[i];
            uint prev_eth_reserves;
            if (addLqdFlag == true) { // This ugly if-else thanks to the "uint" type of amountETH (the best I could think of so far)
                prev_eth_reserves = eth_reserves - amountETH;

                if (addr == msg.sender){
                    lps[msg.sender] = lps[msg.sender] * prev_eth_reserves / eth_reserves + denominator * amountETH / eth_reserves;
                    senderIdx = i;
                }
                else {
                    lps[addr] = lps[addr] * prev_eth_reserves / eth_reserves;
                }
            }
            else {
                prev_eth_reserves = eth_reserves + amountETH;

                if (addr == msg.sender){
                    lps[msg.sender] = lps[msg.sender] * prev_eth_reserves / eth_reserves - denominator * amountETH / eth_reserves;
                    senderIdx = i;
                }
                else {
                    lps[addr] = lps[addr] * prev_eth_reserves / eth_reserves;
                }
            }
            
        }
        return senderIdx;
    }

    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(eth_reserves > 0 && token_reserves > 0, "Insufficient ETH and token liquidity");
        require(msg.value > 0, "Should send non-zero ETH");
        uint amountETH = msg.value;
        uint amountToken = msg.value * token_reserves / eth_reserves;
        require(token.balanceOf(msg.sender) >= amountToken, "Insufficient tokens");


        // need token_reserves / eth_reserves < max_exchange_rate
        require (token_reserves < max_exchange_rate * eth_reserves / denominator, "max slippage triggered");
        // need token_reserves / eth_reserves > min_exchange_rate
        require (token_reserves > min_exchange_rate * eth_reserves / denominator, "min slippage triggered");

        // Transfer tokens, ETH 
        token.transferFrom(msg.sender, address(this), amountToken);
        token_reserves += amountToken;
        eth_reserves += amountETH; 
        k = token_reserves * eth_reserves;

        // Update lps
        if (isNewLpProvider(msg.sender)){
            lp_providers.push(msg.sender);
            lps[msg.sender] = 0;
        }

        updateProportions(amountETH, true);

    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        require(eth_reserves > 0 && token_reserves > 0, "Insufficient ETH and token liquidity");
        require(amountETH > 0, "Should withdraw non-zero ETH");
        require(amountETH < eth_reserves, "ETH reserves depleted");

        // require(isNewLpProvider(msg.sender) == false, "New user has no savings");
        uint maxETH = lps[msg.sender] * eth_reserves / denominator;
        require(amountETH <= maxETH, "Please withdraw less than all savings"); 

        uint amountToken = amountETH * token_reserves / eth_reserves;
        require(amountToken < token_reserves, "Token reserves depleted");

        // need token_reserves / eth_reserves < max_exchange_rate
        require (token_reserves < max_exchange_rate * eth_reserves / denominator, "max slippage triggered");
        // need token_reserves / eth_reserves > min_exchange_rate
        require (token_reserves > min_exchange_rate * eth_reserves / denominator, "min slippage triggered");
        

        // Transfer out tokens, ETH 
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountToken);
        token_reserves -= amountToken;
        eth_reserves -= amountETH; 
        k = token_reserves * eth_reserves;

        // Update lps
        uint senderIdx = updateProportions(amountETH, false);
        if (lps[msg.sender] == 0 && lps_reward_eth[msg.sender] == 0 && lps_reward_token[msg.sender] == 0 ){
            removeLP(senderIdx);
        }

        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");

    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        require(eth_reserves > 0 && token_reserves > 0, "Insufficient liquidity");
        require(isNewLpProvider(msg.sender) == false, "New user has no savings");

        // need token_reserves / eth_reserves < max_exchange_rate
        require (token_reserves < max_exchange_rate * eth_reserves / denominator, "max slippage triggered");
        // need token_reserves / eth_reserves > min_exchange_rate
        require (token_reserves > min_exchange_rate * eth_reserves / denominator, "min slippage triggered");

        uint amountETH = lps[msg.sender] * eth_reserves / denominator;
        require(amountETH < eth_reserves, "ETH reserves depleted");

        uint amountToken = amountETH * token_reserves / eth_reserves;
        require(amountToken < token_reserves, "Token reserves depleted");

        // Transfer out tokens, ETH 
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountToken);
        token_reserves -= amountToken;
        eth_reserves -= amountETH; 
        k = token_reserves * eth_reserves;

        uint senderIdx = updateProportions(amountETH, false);

        uint reward_eth = lps_reward_eth[msg.sender] / denominator;
        uint reward_token = lps_reward_token[msg.sender] / denominator;

        payable(msg.sender).transfer(reward_eth);
        token.transfer(msg.sender, reward_token);

        uint reward_eth_withdrawed = Math.max(reward_eth, reward_token * eth_reserves / token_reserves);
        uint reward_token_withdrawed = reward_eth_withdrawed * token_reserves / eth_reserves;

        eth_reserves -= reward_eth_withdrawed;
        token_reserves -= reward_token_withdrawed;
        k = token_reserves * eth_reserves;


        uint prev_eth_reserves = eth_reserves + reward_eth_withdrawed;
        // below basically is removing liquidity (removing eth from feeAddr & update proportions) 
        for (uint i = 0; i < lp_providers.length; i++) {
            address addr = lp_providers[i];
            if (addr == feeAddr){
                lps[feeAddr] = lps[feeAddr] * prev_eth_reserves / eth_reserves - denominator * reward_eth_withdrawed / eth_reserves;
            } else {
                lps[addr] = lps[addr] * prev_eth_reserves / eth_reserves;
            }
        }

        // because we removed proportional reward_eth_withdrawed & reward_token_withdrawed
        // to preserve k, there might be eth or token (rewards) taken out of the reserves
        // that needs to be put into token_fee_pool or eth_fee_pool
        if (reward_eth_withdrawed == reward_eth) {
            // put back token
            token_fee_pool += reward_token_withdrawed - reward_token;
            require(reward_token_withdrawed - reward_token >= 0, "reward error");
        } else {
            // put back eth
            eth_fee_pool += reward_eth_withdrawed - reward_eth;
            require(reward_eth_withdrawed - reward_eth >= 0, "reward error");
        }


        // finally, remove LP
        removeLP(senderIdx);

        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");
        
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");


        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to swap for eth");
        require (amountTokens > 0, "Need tokens to swap.");

        // need token_reserves / eth_reserves < max_exchange_rate
        require (token_reserves < max_exchange_rate * eth_reserves / denominator, "slippage triggered");

        token.transferFrom(msg.sender, address(this), amountTokens);


        uint token_fee_amount = amountTokens * swap_fee_numerator / swap_fee_denominator;
        amountTokens = amountTokens - token_fee_amount;

        token_fee_pool += token_fee_amount;
        fee_reward_token(token_fee_amount);
        if (eth_fee_pool != 0) {
            reinvest();
        }

        token_reserves += amountTokens;
        uint new_eth_reserves = k / token_reserves;
        uint eth_to_send = eth_reserves - new_eth_reserves;
        eth_reserves = new_eth_reserves;

        payable(msg.sender).transfer(eth_to_send);

        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");

    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");

        // need eth_reserves / token_reserves < max_exchange_rate
        require (eth_reserves < max_exchange_rate * token_reserves / denominator, "slippage triggered");

        uint eth_amount = msg.value;
        uint eth_fee_amount = eth_amount * swap_fee_numerator / swap_fee_denominator;
        eth_amount = eth_amount - eth_fee_amount;

        eth_fee_pool += eth_fee_amount;
        fee_reward_eth(eth_fee_amount);
        if (token_fee_pool != 0) {
            reinvest();
        }

        eth_reserves += eth_amount;

        uint new_token_reserves = k / eth_reserves;
        uint token_amount_to_send = token_reserves - new_token_reserves;
        token_reserves = new_token_reserves;

        token.transfer(msg.sender, token_amount_to_send);

        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");
    }
}
