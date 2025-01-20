// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Mirrortable
 * @notice A minimal on-chain "mirror" of a cap table, with multiple share classes,
 *         the ability to invest via an ERC20 (e.g. USDC), and optional restricted transfers.
 */
contract Mirrortable is Ownable {
    // --------------------------------
    // Structs & Storage
    // --------------------------------

    /// @dev Represents a share class (e.g. "Seed", "Series A", "Common")
    struct ShareClass {
        string name; // display name
        uint256 pricePerShare; // in token terms (e.g. 1e6 = 1 USDC if 6 decimals)
        uint256 totalShares; // how many shares remain to be sold/issued in this class
        bool restrictedTransfer; // if true, only KYC-whitelisted wallets can hold or transfer
    }

    // shareClassId => ShareClass
    mapping(uint256 => ShareClass) public shareClasses;
    uint256 public shareClassCount;

    // investor => (shareClassId => balance)
    mapping(address => mapping(uint256 => uint256)) public sharesBalanceOf;

    // Some optional "compliance oracle" for KYC gating.
    // e.g. This could be a contract that you call to check if an address is whitelisted.
    address public complianceOracle;

    // --------------------------------
    // Events
    // --------------------------------

    event ShareClassCreated(
        uint256 indexed shareClassId,
        string name,
        uint256 pricePerShare,
        uint256 totalShares,
        bool restrictedTransfer
    );

    event ShareClassUpdated(
        uint256 indexed shareClassId,
        uint256 pricePerShare,
        uint256 totalShares,
        bool restrictedTransfer
    );

    event Invested(
        address indexed investor,
        uint256 indexed shareClassId,
        uint256 amountToken,
        uint256 sharesIssued
    );

    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 indexed shareClassId,
        uint256 amount
    );

    // --------------------------------
    // Constructor
    // --------------------------------

    constructor() Ownable(msg.sender) {}

    // --------------------------------
    // Admin / Owner Functions
    // --------------------------------

    /**
     * @dev Owner can set the compliance oracle address
     *      which is used to enforce restricted transfers/investments.
     */
    function setComplianceOracle(address _oracle) external onlyOwner {
        complianceOracle = _oracle;
    }

    /**
     * @dev Create a new share class.
     * @param _name display name for the share class (e.g. "SeedRound")
     * @param _pricePerShare cost in ERC20 token units for each share (e.g. 1 USDC = 1e6 if 6 decimals)
     * @param _totalShares how many shares are available in this class
     * @param _restrictedTransfer if true, only whitelisted addresses can hold or transfer
     */
    function createShareClass(
        string memory _name,
        uint256 _pricePerShare,
        uint256 _totalShares,
        bool _restrictedTransfer
    ) external onlyOwner {
        uint256 newId = shareClassCount;
        shareClasses[newId] = ShareClass({
            name: _name,
            pricePerShare: _pricePerShare,
            totalShares: _totalShares,
            restrictedTransfer: _restrictedTransfer
        });

        emit ShareClassCreated(
            newId,
            _name,
            _pricePerShare,
            _totalShares,
            _restrictedTransfer
        );

        shareClassCount++;
    }

    /**
     * @dev Update existing share class parameters.
     * @param _id the share class ID
     * @param _pricePerShare new price
     * @param _totalShares new total shares
     * @param _restrictedTransfer new restriction flag
     */
    function updateShareClass(
        uint256 _id,
        uint256 _pricePerShare,
        uint256 _totalShares,
        bool _restrictedTransfer
    ) external onlyOwner {
        require(_id < shareClassCount, "Invalid shareClassId");
        shareClasses[_id].pricePerShare = _pricePerShare;
        shareClasses[_id].totalShares = _totalShares;
        shareClasses[_id].restrictedTransfer = _restrictedTransfer;
        emit ShareClassUpdated(
            _id,
            _pricePerShare,
            _totalShares,
            _restrictedTransfer
        );
    }

    // --------------------------------
    // Public / Investor Functions
    // --------------------------------

    /**
     * @dev Invest in a specific share class by sending an approved amount of ERC20 tokens.
     *      For example, if pricePerShare=1e6 (1 USDC) and you pass _amountToken=500e6,
     *      you'll get 500 shares (assuming enough shares remain).
     *
     *      Flow:
     *      1) Investor calls token.approve(thisContract, _amountToken)
     *      2) Investor calls invest(_shareClassId, _amountToken, tokenAddress)
     */
    function invest(
        uint256 _shareClassId,
        uint256 _amountToken,
        address _paymentToken
    ) external {
        require(_shareClassId < shareClassCount, "Invalid shareClassId");
        ShareClass storage sc = shareClasses[_shareClassId];
        require(sc.pricePerShare > 0, "Not open for investment");
        require(_amountToken > 0, "Need a positive token amount");

        // Check restricted
        if (sc.restrictedTransfer) {
            require(_checkKYC(msg.sender), "Not whitelisted");
        }

        // Transfer tokens from investor to contract owner (or to treasury address)
        bool success = IERC20(_paymentToken).transferFrom(
            msg.sender,
            owner(),
            _amountToken
        );
        require(success, "ERC20 transfer failed");

        // Compute # shares
        uint256 sharesToIssue = _amountToken / sc.pricePerShare;
        require(sharesToIssue <= sc.totalShares, "Not enough shares left");

        // Update share class
        sc.totalShares -= sharesToIssue;

        // Update investor's balance
        sharesBalanceOf[msg.sender][_shareClassId] += sharesToIssue;

        emit Invested(msg.sender, _shareClassId, _amountToken, sharesToIssue);
    }

    /**
     * @dev Transfer shares from msg.sender to another address.
     *      If restricted, both parties must pass KYC.
     */
    function transferShares(
        address _to,
        uint256 _shareClassId,
        uint256 _amount
    ) external {
        require(_shareClassId < shareClassCount, "Invalid shareClassId");
        require(_to != address(0), "Can't transfer to zero address");
        require(_amount > 0, "Invalid share amount");

        uint256 senderBalance = sharesBalanceOf[msg.sender][_shareClassId];
        require(senderBalance >= _amount, "Not enough shares");

        ShareClass memory sc = shareClasses[_shareClassId];

        // If restricted, check KYC
        if (sc.restrictedTransfer) {
            require(_checkKYC(msg.sender), "Sender not whitelisted");
            require(_checkKYC(_to), "Receiver not whitelisted");
        }

        // Transfer
        sharesBalanceOf[msg.sender][_shareClassId] = senderBalance - _amount;
        sharesBalanceOf[_to][_shareClassId] += _amount;

        emit TransferShares(msg.sender, _to, _shareClassId, _amount);
    }

    // --------------------------------
    // Internal Helpers
    // --------------------------------

    /**
     * @dev Check if a given account is whitelisted (or if complianceOracle is unset, default = true).
     */
    function _checkKYC(address _account) internal view returns (bool) {
        if (complianceOracle == address(0)) {
            return true; // no KYC check
        }
        // If you have a real interface:
        // return IComplianceOracle(complianceOracle).isWhitelisted(_account);
        // For MVP:
        return true;
    }
}
