// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Common types and interface for all Policies.
interface IPolicy {
    /// High-level policy evaluation result.
    enum PolicyStatus {
        Unknown,
        Pass,
        Fail,
        Pending
    }

    /// Logical role of a party in the transaction.
    enum PartyRole {
        Unknown,
        OriginatorCustomer,
        BeneficiaryCustomer,
        OriginatingVASP,
        BeneficiaryVASP,
        IntermediaryVASP
    }

    /// Party packet: role + wallet + opaque identity references.
    struct PartyPacket {
        PartyRole role;
        address   wallet;
        bytes32   identityRef;
        bytes32   kycHash;
        bytes32   accountRef;
        bytes32   jurisdiction;
    }

    /// Transaction Envelope passed into the compliance pipeline.
    struct TransactionEnvelope {
        address       token;
        uint256       amount;
        uint256       timestamp;
        bytes         extraData;
        PartyPacket[] parties;
    }

    /// Per-policy evaluation record.
    struct PolicyResult {
        bytes32      policyId;
        uint64       policyVersion;
        PolicyStatus status;
        uint256      evaluatedAt;
        bytes        attestationProof;
    }

    /// Aggregated compliance attestation for a given envelope.
    struct ComplianceAttestation {
        bytes32        envelopeHash;
        PolicyStatus   overallStatus;
        PolicyResult[] policyResults;
    }

    // --- Policy identity ---

    function policyId() external view returns (bytes32);

    function policyVersion() external view returns (uint64);

    // --- Core evaluation ---

    /// @notice Evaluate this policy on a given Transaction Envelope.
    /// @return status   PASS/FAIL/PENDING.
    /// @return proof    Policy-specific proof blob (optional / free-form).
    function evaluate(
        TransactionEnvelope calldata envelope
    ) external returns (PolicyStatus status, bytes memory proof);
}
