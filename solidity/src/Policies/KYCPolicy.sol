// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPolicy.sol";

/// @notice Simple KYC policy:
///         - Fails if any required party has an empty kycHash.
///         - Passes otherwise.
///         - Never returns Pending.
contract KYCPolicy is IPolicy {
    bytes32 private immutable _policyId;
    uint64 private immutable _policyVersion;

    /// @notice If true, require KYC for originator-side customer.
    bool public requireOriginatorCustomerKyc;

    /// @notice If true, require KYC for beneficiary-side customer.
    bool public requireBeneficiaryCustomerKyc;

    /// @notice If true, require KYC for VASPs (originating / beneficiary / intermediary).
    bool public requireVaspKyc;

    constructor(
        uint64 version_,
        bool _requireOriginatorCustomerKyc,
        bool _requireBeneficiaryCustomerKyc,
        bool _requireVaspKyc
    ) {
        _policyId = keccak256("KYC_POLICY");
        _policyVersion = version_;

        requireOriginatorCustomerKyc = _requireOriginatorCustomerKyc;
        requireBeneficiaryCustomerKyc = _requireBeneficiaryCustomerKyc;
        requireVaspKyc = _requireVaspKyc;
    }

    // ---------------------------------------------------------------------
    // IPolicy metadata
    // ---------------------------------------------------------------------

    function policyId() external view override returns (bytes32) {
        return _policyId;
    }

    function policyVersion() external view override returns (uint64) {
        return _policyVersion;
    }

    // ---------------------------------------------------------------------
    // Evaluation
    // ---------------------------------------------------------------------

    /// @notice Evaluate KYC policy for all relevant parties in the envelope.
    /// @dev This policy never returns PENDING — only PASS or FAIL.
    /// @param envelope TransactionEnvelope populated by PolicyManager.
    /// @return status PASS or FAIL.
    /// @return proof  Encoded details of which party indices failed (if any).
    function evaluate(
        TransactionEnvelope calldata envelope
    ) external view override returns (PolicyStatus status, bytes memory proof) {
        uint256 partiesLen = envelope.parties.length;

        // Track failing party indices for the proof blob.
        uint256[] memory failing = new uint256[](partiesLen);
        uint256 failCount = 0;

        for (uint256 i = 0; i < partiesLen; i++) {
            PartyPacket calldata p = envelope.parties[i];

            bool requireKycForThisParty = _requiresKycForRole(
                p.role,
                requireOriginatorCustomerKyc,
                requireBeneficiaryCustomerKyc,
                requireVaspKyc
            );

            if (requireKycForThisParty) {
                // In this simple PoC, "valid KYC" == non-zero kycHash.
                // This will need to be replaced by a more robust check in a full implementation
                if (p.kycHash == bytes32(0)) {
                    failing[failCount] = i;
                    failCount++;
                }
            }
        }

        if (failCount == 0) {
            // No failures → PASS.
            return (PolicyStatus.Pass, bytes(""));
        }

        // At least one required party has no KYC → FAIL.
        // Encode only the failing indices for compactness.
        // Consumers can decode as: (uint256[] failingIndices, uint256 count).
        bytes memory encodedProof = abi.encode(failing, failCount);
        return (PolicyStatus.Fail, encodedProof);
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    /// @notice Decide whether a given role is subject to KYC in this policy.
    /// @dev Made internal+pure and parameterised so the behaviour is explicit.
    function _requiresKycForRole(
        PartyRole role,
        bool originatorCustomerRequired,
        bool beneficiaryCustomerRequired,
        bool vaspRequired
    ) internal pure returns (bool) {
        if (role == PartyRole.OriginatorCustomer) {
            return originatorCustomerRequired;
        }

        if (role == PartyRole.BeneficiaryCustomer) {
            return beneficiaryCustomerRequired;
        }

        if (
            role == PartyRole.OriginatingVASP ||
            role == PartyRole.BeneficiaryVASP ||
            role == PartyRole.IntermediaryVASP
        ) {
            return vaspRequired;
        }

        // Unknown or unrecognised roles → no KYC requirement by default.
        return false;
    }
}
