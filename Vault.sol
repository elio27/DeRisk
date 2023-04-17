// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract Vault {

    error Unauthorized();
    modifier _onlyController() {
        if (msg.sender != controller) {
            revert Unauthorized();
        }
        _;
    }

    address public controller;
    uint256 public marketIndex;
    mapping(address => uint256) internal shares;
    uint256 public totalShares;

    constructor(uint256 _marketIndex) {
        controller = msg.sender;
        marketIndex = _marketIndex;
    }

    function addDeposit(address _to, uint256 _amount) external _onlyController {
        shares[_to] += _amount;
        totalShares += _amount;
    }

    function addWithdrawal(address _from, uint256 _amount) external _onlyController {
        shares[_from] -= _amount;
    }

    function getSharesOf(address _user) external view returns(uint256) {
        return shares[_user];
    }
    
}
