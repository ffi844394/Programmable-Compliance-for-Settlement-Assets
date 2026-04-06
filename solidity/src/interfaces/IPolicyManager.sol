// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPolicy.sol";

interface IPolicyManager {
    /// Lightweight transaction context coming from the caller (e.g. PolicyWrapper)
    struct TxContext {
        address token;    // underlying asset token (e.g. AssetBackedToken)
        address from;     // source wallet
        address to;       // destination wallet
        uint256 amount;   // transfer amount
        bytes   extraData;// optional ABI-encoded payload (e.g. corporate action refs)
    }

    /// Run all registered policies on a given TxContext.
    /// Implementations are expected to:
    ///  - Enrich identity (via IdentityRegistry or other sources),
    ///  - Build a TransactionEnvelope,
    ///  - Evaluate all policies,
    ///  - Return a ComplianceAttestation.
    function runPolicies(
        TxContext calldata ctx
    ) external returns (IPolicy.ComplianceAttestation memory);
}
