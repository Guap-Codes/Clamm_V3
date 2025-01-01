// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "../interfaces/IERC20.sol";
import "../interfaces/ICLAMM.sol";

/// @title FeeCollector
/// @notice Contract for collecting and managing protocol fees with multi-signature control
/// @dev Requires multiple signatures for administrative actions like changing fee recipient or rescuing funds
contract FeeCollector {
    address public owner;
    address public feeRecipient;
    address[] public signers;
    uint256 public requiredSignatures;

    mapping(address => bool) public isSigner;
    mapping(bytes32 => uint256) public signatureCount;
    mapping(bytes32 => mapping(address => bool)) public hasSigned;

    /// @notice Constructs the FeeCollector contract
    /// @param _feeRecipient Address that will receive collected fees
    /// @param _signers Array of addresses that can sign administrative actions
    /// @param _requiredSignatures Number of signatures required for administrative actions
    /// @dev The number of signers must be greater than or equal to required signatures
    constructor(address _feeRecipient, address[] memory _signers, uint256 _requiredSignatures) {
        require(_signers.length >= _requiredSignatures, "Not enough signers");
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        signers = _signers;
        requiredSignatures = _requiredSignatures;
        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
        }
    }

    /// @notice Restricts function access to authorized signers only
    modifier onlySigner() {
        require(isSigner[msg.sender], "Only signer");
        _;
    }

    /// @notice Collects protocol fees from a CLAMM pool and transfers them to the fee recipient
    /// @param pool Address of the CLAMM pool to collect fees from
    /// @dev Anyone can call this function to trigger fee collection
    function collectFees(ICLAMM pool) external {
        (uint256 amount0, uint256 amount1) = pool.collectProtocolFees(address(this));

        if (amount0 > 0) {
            IERC20(pool.token0()).transfer(feeRecipient, amount0);
        }
        if (amount1 > 0) {
            IERC20(pool.token1()).transfer(feeRecipient, amount1);
        }
    }

    /// @notice Changes the fee recipient address with multi-signature approval
    /// @param _feeRecipient New address to receive fees
    /// @dev Requires requiredSignatures number of unique signer approvals
    /// @dev Resets signature count and signing status after successful change
    function setFeeRecipient(address _feeRecipient) external onlySigner {
        bytes32 txHash = keccak256(abi.encodePacked(_feeRecipient));
        require(!hasSigned[txHash][msg.sender], "Already signed");

        hasSigned[txHash][msg.sender] = true;
        signatureCount[txHash]++;

        if (signatureCount[txHash] >= requiredSignatures) {
            feeRecipient = _feeRecipient;
            // Reset the signature count for this transaction
            signatureCount[txHash] = 0;
            for (uint256 i = 0; i < signers.length; i++) {
                hasSigned[txHash][signers[i]] = false;
            }
        }
    }

    /// @notice Rescues stuck tokens from the contract with multi-signature approval
    /// @param token Address of the ERC20 token to rescue
    /// @param amount Amount of tokens to rescue
    /// @dev Requires requiredSignatures number of unique signer approvals
    /// @dev Resets signature count and signing status after successful rescue
    function rescueFunds(IERC20 token, uint256 amount) external onlySigner {
        bytes32 txHash = keccak256(abi.encodePacked(address(token), amount));
        require(!hasSigned[txHash][msg.sender], "Already signed");

        hasSigned[txHash][msg.sender] = true;
        signatureCount[txHash]++;

        if (signatureCount[txHash] >= requiredSignatures) {
            token.transfer(feeRecipient, amount);
            // Reset the signature count for this transaction
            signatureCount[txHash] = 0;
            for (uint256 i = 0; i < signers.length; i++) {
                hasSigned[txHash][signers[i]] = false;
            }
        }
    }
}
