pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AMM {

    using SafeMath for uint256;

    uint256 totalShares;  // total amt of shares for pool
    uint256 totalToken1;  // amt of tok1 in pool
    uint256 totalToken2;  // amt of tok2 in pool
    uint256 K;  // algo constant for pricing (K = totalToken1 * totalToken2)

    uint256 constant PRECISION = 1_000_000; // 6 place precision constant

    mapping(address => uint256) shares;
    mapping(address => uint256) token1Balance;
    mapping(address => uint256) token2Balance;


    modifier validAmountCheck(mapping(address => uint256) storage _balance, uint256 _qty) {
        require(_qty > 0, "Amount cannot be zero!");
        require(_qty <= _balance[msg.sender], "Insufficent amount");
        _;
    }

    modifier activePool() {
        require(totalShares > 0, "Zero liquidity");
        _;
    }

    function getMyHoldings() external view returns(uint256 amountToken1, uint256 amountToken2, uint256 myShare) {
        amountToken1 = token1Balance[msg.sender];
        amountToken2 = token2Balance[msg.sender];
        myShare = shares[msg.sender];
    }

    function getPoolDetails() external view returns(uint256, uint256, uint256) {
        return (totalToken1, totalToken2, totalShares);
    }

    // Sends free token(s) to invoker
    function faucet(uint256 _amountToken1, uint256 _amountToken2) external {
        token1Balance[msg.sender] = token1Balance[msg.sender].add(_amountToken1);
        token2Balance[msg.sender] = token2Balance[msg.sender].add(_amountToken2);
    }

    // Adding new liquidity in pool
    // Returns amount of share issued for locking assets
    function provide(uint256 _amountToken1, uint256 _amountToken2) external 
        validAmountCheck(token1Balance, _amountToken1) 
        validAmountCheck(token2Balance, _amountToken2)
        returns(uint256 share) 
    {
        if (totalShares == 0) {
            share = 100 * PRECISION;
        }
        else {
            uint256 share1 = totalShares.mul(_amountToken1).div(totalToken1);
            uint256 share2 = totalShares.mul(_amountToken2).div(totalToken2);
            require(share1 == share2, "Equivalent value of tokens not provided...");
            share = share1;
        }

        require(share > 0, "Asset value less than threshold for contribution.");
        token1Balance[msg.sender] -= _amountToken1;
        token2Balance[msg.sender] -= _amountToken2;

        totalToken1 += _amountToken1;
        totalToken2 += _amountToken2;
        K = totalToken1.mul(totalToken2);

        totalShares += share;
        shares[msg.sender] += share;
    }

    function getEquivalentToken1Estimate(uint256 _amountToken2) public view activePool 
        returns(uint256 reqToken1) 
    {
        reqToken1 = totalToken1.mul(_amountToken2).div(totalToken2);
    }

    function getEquivalentToken2Estimate(uint256 _amountToken1) public view activePool 
        returns(uint256 reqToken2) 
    {
        reqToken2 = totalToken2.mul(_amountToken1).div(totalToken1);
    }

    function getWithdrawEstimate(uint256 _share) public view activePool 
        returns(uint256 amountToken1, uint256 amountToken2) 
    {
        require(_share <= totalShares, "Share should be less than totalShare");
        amountToken1 = _share.mul(totalToken1).div(totalShares);
        amountToken2 = _share.mul(totalToken2).div(totalShares);
    }

    function withdraw(uint256 _share) external activePool validAmountCheck(shares, _share) 
        returns(uint256 amountToken1, uint256 amountToken2) 
    {
        (amountToken1, amountToken2) = getWithdrawEstimate(_share);

        shares[msg.sender] -= _share;
        totalShares -= _share;

        totalToken1 -= amountToken1;
        totalToken2 -= amountToken2;
        K = totalToken1.mul(totalToken2);

        token1Balance[msg.sender] += amountToken1;
        token2Balance[msg.sender] += amountToken2;
    }

    function getSwapToken1Estimate(uint256 _amountToken1) public view activePool 
        returns(uint256 amountToken2) 
    {
        uint256 token1After = totalToken1.add(_amountToken1);
        uint256 token2After = K.div(token1After);
        amountToken2 = totalToken2.sub(token2After);

        // check pool depletion leading to div by zero condition
        if (amountToken2 == totalToken2) amountToken2--;
    }

    function getSwapToken1EstimateGivenToken2(uint256 _amountToken2) public view activePool 
        returns(uint256 amountToken1)
    {
        require(_amountToken2 < totalToken2, "Insufficient pool balance");
        uint256 token2After = totalToken2.sub(_amountToken2);
        uint256 token1After = K.div(token2After);
        amountToken1 = token1After.sub(totalToken1);
    }

    function swapToken1(uint256 _amountToken1) external activePool 
        validAmountCheck(token1Balance, _amountToken1)
        returns(uint256 amountToken2) 
    {
        amountToken2 = getSwapToken1Estimate(_amountToken1);
        token1Balance[msg.sender] -= _amountToken1;
        totalToken1 += _amountToken1;
        totalToken2 -= amountToken2;
        token2Balance[msg.sender] += amountToken2;
    }

    // Returns the amount of Token2 that the user will get when swapping a given amount of Token1 for Token2
    function getSwapToken2Estimate(uint256 _amountToken2) public view activePool 
        returns(uint256 amountToken1) 
    {
        uint256 token2After = totalToken2.add(_amountToken2);
        uint256 token1After = K.div(token2After);
        amountToken1 = totalToken1.sub(token1After);

        // To ensure that Token1's pool is not completely depleted leading to inf:0 ratio
        if(amountToken1 == totalToken1) amountToken1--;
    }

    // Returns the amount of Token2 that the user should swap to get _amountToken1 in return
    function getSwapToken2EstimateGivenToken1(uint256 _amountToken1) public view activePool 
        returns(uint256 amountToken2) 
    {
        require(_amountToken1 < totalToken1, "Insufficient pool balance");
        uint256 token1After = totalToken1.sub(_amountToken1);
        uint256 token2After = K.div(token1After);
        amountToken2 = token2After.sub(totalToken2);
    }

    // Swaps given amount of Token2 to Token1 using algorithmic price determination
    function swapToken2(uint256 _amountToken2) external activePool 
        validAmountCheck(token2Balance, _amountToken2) 
        returns(uint256 amountToken1) 
    {
        amountToken1 = getSwapToken2Estimate(_amountToken2);
        token2Balance[msg.sender] -= _amountToken2;
        totalToken2 += _amountToken2;
        totalToken1 -= amountToken1;
        token1Balance[msg.sender] += amountToken1;
    }
}
