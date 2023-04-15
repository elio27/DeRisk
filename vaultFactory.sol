// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

/**
@title Vault Factory
@author DeRisk Finance team
@notice Main contract of the DeRisk protocol
@custom:warning Very early stage
*/
contract vaultFactory {

    address public immutable USDC;
    address public controller;
    address public treasury;
    
    Market[] internal markets;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    event ControllerChange(address _oldController, address _newController);
    event TreasuryChange(address _oldTreasury, address _newTreasury);
    event Deposit(address _from, uint256 _marketIndex, string _side, uint256 _amount);
    event Withdraw(address _from, uint256 _marketIndex, string _side, uint256 _amount);


    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error Unauthorized();
    error ZeroAddress();
    error MarketDoesNotExist();


    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Vault {
        mapping(address => uint256) shares;     /// MAPPING OF USERS'S SHARES
        uint256 totalShares;                    /// TOTAL AMOUNT OF SHARES IN THE VAULT
    }

    struct Market {
        string name;            /// NAME OF THE MARKET
        string token;           /// TICKER OF THE TOKEN
        Vault Hedge;            /// HEDGE VAULT
        Vault Risk;             /// RISK VAULT
        uint256 strike;         /// STRIKE PRICE
        uint256 delta;          /// DELTA
        uint256 upLimit;        /// STRIKE + DELTA
        uint256 downLimit;      /// STRIKE - DELTA
        uint64 depositStart;    /// TIMESTAMP OF THE BEGINNING OF DEPOSIT PERIOD
        uint64 depositEnd;      /// TIMESTAMP OF THE END OF DEPOSIT PERIOD
        uint64 epochStart;      /// TIMESTAMP OF THE BEGINNING OF EPOCH
        uint64 epochEnd;        /// TIMESTAMP OF THE BEGINNING OF EPOCH
        bool triggered;         /// STATE OF THE CONTRACT (ALIVE/TRIGGERED)
    }


    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor (address _usdc, address _controller, address _treasury) {
        if (_usdc == address(0)) {
            revert ZeroAddress();
        }

        if (_controller == address(0)) {
            revert ZeroAddress();
        }

        if (_treasury == address(0)) {
            revert ZeroAddress();
        }

        USDC = _usdc;
        controller = _controller;
        treasury = _treasury;
    }


    function marketExists(uint256 _marketIndex) internal returns(bool) {
        return !(_marketIndex > markets.length);
    }

    /*//////////////////////////////////////////////////////////////
                        CONTROLLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
    @notice Reverts if the caller is not the contract's controller 
    */
    modifier _onlyController() {
        if (msg.sender != controller) {
            revert Unauthorized();
        }
        _;
    }

    /**
    @notice Transfers the ownership of the contract
    @param _controller Address of the new controller
    */
    function changeController(address _controller) external _onlyController {
        if (_controller == address(0)) {
            revert ZeroAddress();
        }
        address oldController = controller;
        controller = _controller;
        emit ControllerChange(oldController, _controller);
    }

    /**
    @notice Change the address of the treasury
    @param _treasury Address of the new treasury
    */
    function changeTreasury(address _treasury) external _onlyController {
        if (_treasury == address(0)) {
            revert ZeroAddress();
        }
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryChange(oldTreasury, _treasury);
    }


    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
    @notice Function caller sends USDC against shares in the Hedge pool
    @param _marketIndex Index  of the wanted market
    @param _amount Amount in USDC (18 decimals) to deposit
    */
    function depositHedge(uint256 _marketIndex, uint256 _amount) external returns(bool) {
        if (!marketExists(_marketIndex)) {
            revert MarketDoesNotExist();
        }

        IERC20(USDC).transferFrom(msg.sender, address(this), _amount);

        markets[_marketIndex].Hedge.shares[msg.sender] += _amount;
        markets[_marketIndex].Hedge.totalShares += _amount;

        emit Deposit(msg.sender, _marketIndex, "HEDGE", _amount);

        return true;
    }

    /**
    @notice Function caller withdraws USDC (if the contract has been triggered)
    @param _marketIndex Index of the wanted market
    */
    function withdrawHedge(uint256 _marketIndex) external returns(bool) {
        if (!marketExists(_marketIndex)) {
            revert MarketDoesNotExist();
        }
        Market memory market = markets[_marketIndex];

        if (market.triggered) {

        }
        else if (market.expiration < block.timestamp) {

        }
        else {
            revert()
        }

        emit Withdraw(msg.sender, _marketIndex, "HEDGE")

        return true;
    }


    /*//////////////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
    @notice Returns the amount of shares owned by an user in the Hedge vault of a market
    @param _marketIndex Index of the wanted market
    @param _user Address of the wanted user
    */
    function getHedgeSharesOf(uint256 _marketIndex, address _user) external view returns(uint256) {
        return markets[_marketIndex].Hedge.shares[_user];
    }

    /**
    @notice Returns the total amount of shares in the Hedge vault of a market
    @param _marketIndex Index of the wanted market
    */
    function getHedgeTotalShares(uint256 _marketIndex) external view returns(uint256) {
        return markets[_marketIndex].Hedge.totalShares;
    }

    /**
    @notice Returns the amount of shares owned by an user in the Risk vault of a market
    @param _marketIndex Index of the wanted market
    @param _user Address of the wanted user
    */
    function getRiskSharesOf(uint256 _marketIndex, address _user) external view returns(uint256) {
        return markets[_marketIndex].Risk.shares[_user];
    }

    /**
    @notice Returns the total amount of shares in the Risk vault of a market
    @param _marketIndex Index of the wanted market
    */
    function getRiskTotalShares(uint256 _marketIndex) external view returns(uint256) {
        return markets[_marketIndex].Risk.totalShares;
    }

}
