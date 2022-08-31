// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20 Token Contract
 */
contract Token is ERC20, Ownable {
    constructor() 
        ERC20("Gold", "GLD") 
    {
        _mint(msg.sender, 10 * 10**18);
    }

    /**
     * @notice Mint function
     * @param to The address of a receiver account
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) 
        public 
        onlyOwner 
    {
        _mint(to, amount);
    }
}

/**
 * @title Escapable Contract
 */
contract Escapable is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public escapeHatchDestination;
    // tokens are declared immutable but unfortunately immutable state variables cannot be read at construction time
    IERC20 public token;

    event EscapeHatchCalled(
        uint256 amount
    );

    constructor(
        address _escapeHatchDestination,
        address _tokenAddress
    ) {
        escapeHatchDestination = _escapeHatchDestination;
        token = Token(_tokenAddress);
    }

    function escapeHatch() 
        public
        onlyOwner
    {
        uint256 tokenTotal = token.balanceOf(address(this));
        uint256 etherTotal = address(this).balance;

        if (tokenTotal > 0) {
            token.safeTransfer(escapeHatchDestination, tokenTotal);
        }

        if (etherTotal > 0) {
            (bool success, ) = escapeHatchDestination.call{value: etherTotal}("");
            require(success, "Failed to send Ether");
        }

        emit EscapeHatchCalled(tokenTotal);
    }
}

/**
 * @title Vault Contract
 */
contract Vault is Ownable, Escapable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Payment {
        string name;
        address spender;
        uint256 earliestPayTime;
        bool canceled;
        bool paid;
        address recipient;
        uint256 amount;
        uint256 securityGuardDelay;
        bool added;
        bool currency;
    }

    struct AllowedSpender {
        bool authorize;
        bool isDeleted;
        bool added;
    }

    address tokenAddress;
    address public securityGuard;
    uint256 public absoluteMinTimeLock;
    uint256 public timeLock;
    uint256 public maxSecurityGuardDelay;
    mapping(bytes32 => Payment) authorizedPayments;
    mapping(address => AllowedSpender) allowedSpenders;

    event Deposited(
        address indexed add, 
        uint256 amount
    );

    event Withdrawn(
        address indexed add,
        uint256 amount
    );

    event SpenderAuthorization(
        address indexed spender, 
        bool authorized
    );

    event PaymentAuthorized(
        bytes32 indexed idPayment,
        address indexed recipient,
        uint256 amount,
        bool currency
    );

    event PaymentCanceled(
        bytes32 indexed idPayment
    );

    event PaymentExecuted(
        bytes32 indexed idPayment,
        address indexed recipient,
        uint256 amount,
        bool currency
    );

    event EtherDeposited(
        address add,
        uint256 amount
    );

    modifier onlySecurityGuard() {
        require(msg.sender == securityGuard, "not sender");
        _;
    }

    modifier onlyAllowedSpender() {
        require(
            (allowedSpenders[msg.sender].authorize &&
                !allowedSpenders[msg.sender].isDeleted),
            "not authorized for payment"
        );
        _;
    }

    constructor(
        address _escapeHatchDestination,
        address _tokenAddress,
        uint256 _timeLock,
        uint256 _absoluteMinTimeLock,
        address _securityGuard,
        uint256 _maxSecurityGuardDelay
    ) 
        Escapable(
        _escapeHatchDestination,
        _tokenAddress
    ) {
        token = Token(_tokenAddress);
        tokenAddress = _tokenAddress;
        absoluteMinTimeLock = _absoluteMinTimeLock;
        timeLock = _timeLock;
        securityGuard = _securityGuard;
        maxSecurityGuardDelay = _maxSecurityGuardDelay;
    }

    receive() external payable {
        require(msg.value > 0, "Send some eth to deposit");
        emit EtherDeposited(msg.sender, msg.value);
    }

    function depositToken(uint amount) external payable {
        require(amount > 0, "Send some tokens to deposit");
        require(
            token.balanceOf(msg.sender) >= amount,
            "Your token amount must be greater then you are trying to deposit"
        );
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "Approve tokens first!"
        );
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function authorizeSpender(address _spender, bool _authorize)
        public
        onlyOwner
    {
        allowedSpenders[_spender]= AllowedSpender(_authorize, false, true);
        emit SpenderAuthorization(_spender, _authorize);
    }

    function authorizePayment(
        string calldata _name,
        address _recipient,
        uint256 _amount,
        uint256 _paymentDelay,
        bool _currency
    ) 
        public 
        onlyAllowedSpender 
        returns (bytes32) 
    {
        bytes32 idPayment = keccak256(
            abi.encodePacked(_name, _recipient, _amount, msg.sender)
        );

        uint payTime = _paymentDelay >=
            timeLock
            ? block.timestamp.add(_paymentDelay)
            : block.timestamp.add(timeLock);

        authorizedPayments[idPayment]= 
            Payment(
                _name, 
                msg.sender, 
                payTime, 
                false, 
                false, 
                _recipient, 
                _amount, 
                0, 
                true, 
                _currency
            );

        emit PaymentAuthorized(
            idPayment,
            authorizedPayments[idPayment].recipient,
            authorizedPayments[idPayment].amount,
            authorizedPayments[idPayment].currency
        );
        return idPayment;
    }

    function collectAuthorizedPayment(bytes32 _idPayment)
        public
        onlyAllowedSpender
    {
        require(authorizedPayments[_idPayment].added, "payment doesn't exist");
        require(
            block.timestamp > authorizedPayments[_idPayment].earliestPayTime,
            "time not passed yet"
        );
        require(!authorizedPayments[_idPayment].canceled, "canceled payment");
        require(!authorizedPayments[_idPayment].paid, "paid already payment");

        authorizedPayments[_idPayment].paid = true;
        if (authorizedPayments[_idPayment].currency) {
            (bool sent, ) = authorizedPayments[_idPayment].recipient.call{
                            value: authorizedPayments[_idPayment].amount
                            }("");
            require(sent, "eth failed to be sent");
        } else {
            token.safeTransfer(
            authorizedPayments[_idPayment].recipient,
            authorizedPayments[_idPayment].amount
            );
        }

        emit PaymentExecuted(
            _idPayment,
            authorizedPayments[_idPayment].recipient,
            authorizedPayments[_idPayment].amount,
            authorizedPayments[_idPayment].currency
        );
    }

    function cancelPayment(bytes32 _idPayment) 
        public 
        onlyOwner 
    {
        require(authorizedPayments[_idPayment].added, "payment doesn't exist");
        require(!authorizedPayments[_idPayment].canceled, "already canceled");
        require(!authorizedPayments[_idPayment].paid, "already paid");

        authorizedPayments[_idPayment].canceled = true;
        emit PaymentCanceled(_idPayment);
    }

    function setSecurityGuard(address _newSecurityGuard) 
        public 
        onlyOwner 
    {
        securityGuard = _newSecurityGuard;
    }

    function setTimelock(uint256 _newTimeLock) 
        public 
        onlyOwner 
    {
        require(
            _newTimeLock > absoluteMinTimeLock,
            "new time should be greater than min"
        );
        timeLock = _newTimeLock;
    }

    function delayPayment(bytes32 _idPayment, uint256 _delay)
        public
        onlySecurityGuard
    {
        require(authorizedPayments[_idPayment].added, "payment doesn't exist");
        require(_delay < 10**18, "overflow");

        require(
            (authorizedPayments[_idPayment].securityGuardDelay.add(_delay) <
                maxSecurityGuardDelay) ||
                (!authorizedPayments[_idPayment].paid) ||
                (!authorizedPayments[_idPayment].canceled),
            "cannot proceed"
        );

        authorizedPayments[_idPayment].securityGuardDelay = authorizedPayments[
            _idPayment].securityGuardDelay.add(_delay);
        authorizedPayments[_idPayment].earliestPayTime = authorizedPayments[
            _idPayment].earliestPayTime.add(_delay);
    }

    function removeWhitelist(address _address) 
        public 
        onlyOwner
    {
        require(allowedSpenders[_address].added, "doesn't exist to remove");
        allowedSpenders[_address] = AllowedSpender(false,true,false);
    }
}