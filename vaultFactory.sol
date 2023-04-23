// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IERC20.sol";
import "./AggregatorV3Interface.sol";
import {Vault} from "./Vault.sol";

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
    
    Market[] public markets;
    mapping(string => Oracle) public oracles;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    event ControllerChange(address _oldController, address _newController);
    event TreasuryChange(address _oldTreasury, address _newTreasury);
    event Deposit(address _from, uint256 _marketIndex, string _side, uint256 _amount);
    event Withdraw(address _to, uint256 _marketIndex, string _side, uint256 _amount);
    event Trigger(uint256 _marketIndex, uint256 _timestamp);


    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error Unauthorized();
    error ZeroAddress();
    error MarketDoesNotExist();
    error MarketIsStillActive();
    error MarketIsInactive();
    error MarketHasNotStarted();
    error NothingToClaim();
    error PriceInRange();


    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Market {
        string  name;            /// NAME OF THE MARKET
        string  token;           /// TICKER OF THE TOKEN
        uint256 decimals;       /// AMOUNT OF DECIMALS USED FOR THE STRIKE PRICE AND THE DELTA
        Vault   Hedge;
        Vault   Risk;
        uint256 strike;         /// STRIKE PRICE
        uint256 delta;          /// DELTA
        uint256 upLimit;        /// STRIKE + DELTA
        uint256 downLimit;      /// STRIKE - DELTA
        uint64  depositStart;   /// TIMESTAMP OF THE BEGINNING OF DEPOSIT PERIOD
        uint64  depositEnd;     /// TIMESTAMP OF THE END OF DEPOSIT PERIOD
        uint64  epochStart;     /// TIMESTAMP OF THE BEGINNING OF EPOCH
        uint64  epochEnd;       /// TIMESTAMP OF THE BEGINNING OF EPOCH
        bool    triggered;      /// STATE OF THE CONTRACT (ALIVE/TRIGGERED)
    }

    struct Oracle {
        address oracleAddress;  /// ADDRESS OF THE PRICE FEED
        uint256 decimals;       /// DECIMALS OF THE PRICE FEED
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


    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function marketExists(uint256 _marketIndex) internal view returns(bool) {
        return _marketIndex < markets.length;
    }

    function tokenExists(string memory _token) internal view returns(bool) {
        return oracles[_token].oracleAddress != address(0);
    }

    function isActive(uint256 _marketIndex) internal view returns(bool) {
        Market memory market = markets[_marketIndex];
        return (block.timestamp >= market.epochStart) && (block.timestamp < market.epochEnd) && !market.triggered;
    }

    function isTriggered(uint256 _marketIndex) internal view returns(bool) {
        return markets[_marketIndex].triggered;
    }

    function isExpired(uint256 _marketIndex) internal view returns(bool) {
        return block.timestamp >= markets[_marketIndex].epochEnd;
    }

    function isTriggeredOrExpired(uint256 _marketIndex) internal view returns(bool) {
        return isTriggered(_marketIndex) || isExpired(_marketIndex);
    }


    /*//////////////////////////////////////////////////////////////
                        ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getPrice(string memory _token) internal view returns(uint256, uint256) {
        Oracle memory priceFeed = oracles[_token];

        (, int256 p, , , ) = AggregatorV3Interface(priceFeed.oracleAddress).latestRoundData();

        return (uint256(p), priceFeed.decimals);
    }

    function trigger(uint256 _marketIndex) external {
        if (!marketExists(_marketIndex)) {
            revert MarketDoesNotExist();
        }
        if (!isActive(_marketIndex)) {
            revert MarketIsInactive();
        }
        
        Market memory market = markets[_marketIndex];
        (uint256 price, uint256 decimals) = getPrice(market.token);

        above = price*market.decimals > market.upLimit*decimals;
        under = price*market.decimals < market.downLimit*decimals;

        if (above || under) {
            markets[_marketIndex].triggered = true;
            emit Trigger(_marketIndex, block.timestamp);
        }
        else {
            revert PriceInRange();
        }
        
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

    /**
    @notice Add a new oracle
    @param _token Ticker of the token
    @param _oracleAddress Address of the new pricefeed
    @param _decimals Decimals of the pricefeed
    */
    function addOracle(string memory _token, address _oracleAddress, uint256 _decimals) external _onlyController {
        if (_oracleAddress == address(0)) {
            revert ZeroAddress();
        }

        oracles[_token] = Oracle(_oracleAddress, _decimals);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
    @notice Create a new Market
    @param _name Name of the market
    @param _token Ticker of the token
    @param _decimals Number of decimals used
    @param _strike Strike price of the contract
    @param _delta Delta of the contract
    @param _depositEnd Timestamp of the end of the deposit period
    @param _epochStart Timestamp of the beginning of the activity of the contract
    @param _epochEnd Timestamp of the expiration od the contract
    */
    function createMarket(
        string memory _name,
        string memory _token,
        uint256 _decimals,
        uint256 _strike,
        uint256 _delta,
        uint64 _depositEnd,
        uint64 _epochStart,
        uint64 _epochEnd
        ) external _onlyController returns(uint256) {
            uint256 marketIndex = markets.length;
            Market memory market = Market(
                _name,
                _token,
                _decimals,
                new Vault(marketIndex),
                new Vault(marketIndex),
                _strike,
                _delta,
                _strike + _delta,
                _strike - _delta,
                uint64(block.timestamp),
                _depositEnd,
                _epochStart,
                _epochEnd,
                false
                );

            markets.push(market);
            return marketIndex;
        }

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

        markets[_marketIndex].Hedge.addDeposit(msg.sender, _amount);

        emit Deposit(msg.sender, _marketIndex, "HEDGE", _amount);

        return true;
    }

    /**
    @notice Function caller sends USDC against shares in the Risk pool
    @param _marketIndex Index  of the wanted market
    @param _amount Amount in USDC (18 decimals) to deposit
    */
    function depositRisk(uint256 _marketIndex, uint256 _amount) external returns(bool) {
        if (!marketExists(_marketIndex)) {
            revert MarketDoesNotExist();
        }

        IERC20(USDC).transferFrom(msg.sender, address(this), _amount);

        markets[_marketIndex].Risk.addDeposit(msg.sender, _amount);

        emit Deposit(msg.sender, _marketIndex, "RISK", _amount);

        return true;
    }

    /**
    @notice Function caller withdraws risk Hedgor's premium in USDC (if the contract has not been triggered)
    @param _marketIndex Index of the wanted market
    */
    function withdrawRisk(uint256 _marketIndex) external returns(bool) {
        if (!marketExists(_marketIndex)) {
            revert MarketDoesNotExist();
        }

        if (!isExpired(_marketIndex)) {
            revert MarketIsStillActive();
        }
        
        Market memory market = markets[_marketIndex];
        uint256 amount = market.Risk.getSharesOf(msg.sender) * market.Hedge.totalShares() / market.Risk.totalShares();

        if (market.triggered) {
            amount += market.Risk.getSharesOf(msg.sender);
        }

        market.Risk.addWithdrawal(msg.sender, amount);
        IERC20(USDC).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, _marketIndex, "Risk", amount);

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

        if (!isTriggeredOrExpired(_marketIndex)) {
            revert MarketIsStillActive();
        }

        Market memory market = markets[_marketIndex];
        uint256 amount;

        if (market.triggered) {
            amount = market.Hedge.getSharesOf(msg.sender) * market.Risk.totalShares() / market.Hedge.totalShares();
        }
        else {
            revert NothingToClaim();
        }

        market.Hedge.addWithdrawal(msg.sender, amount);
        IERC20(USDC).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, _marketIndex, "HEDGE", amount);

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
        return markets[_marketIndex].Hedge.getSharesOf(_user);
    }

    /**
    @notice Returns the total amount of shares in the Hedge vault of a market
    @param _marketIndex Index of the wanted market
    */
    function getHedgeTotalShares(uint256 _marketIndex) external view returns(uint256) {
        return markets[_marketIndex].Hedge.totalShares();
    }

    /**
    @notice Returns the amount of shares owned by an user in the Risk vault of a market
    @param _marketIndex Index of the wanted market
    @param _user Address of the wanted user
    */
    function getRiskSharesOf(uint256 _marketIndex, address _user) external view returns(uint256) {
        return markets[_marketIndex].Risk.getSharesOf(_user);
    }

    /**
    @notice Returns the total amount of shares in the Risk vault of a market
    @param _marketIndex Index of the wanted market
    */
    function getRiskTotalShares(uint256 _marketIndex) external view returns(uint256) {
        return markets[_marketIndex].Risk.totalShares();
    }

}
