// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPolicy.sol";
import "../interfaces/IPolicyManager.sol";

abstract contract PolicyProtected {
    event PolicyManagerUpdated(
        address indexed oldManager,
        address indexed newManager
    );

    address public policyManager;

    function __PolicyProtected_init(address _policyManager) internal {
        require(_policyManager != address(0), "PolicyProtected: manager is zero");
        policyManager = _policyManager;
        emit PolicyManagerUpdated(address(0), _policyManager);
    }

    function _setPolicyManager(address _policyManager) internal {
        require(_policyManager != address(0), "PolicyProtected: manager is zero");
        emit PolicyManagerUpdated(policyManager, _policyManager);
        policyManager = _policyManager;
    }

    /// @notice Internal helper to run policies and return the full attestation.
    function _runPolicies(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory extraData
    ) internal returns (IPolicy.ComplianceAttestation memory attestation) {
        if (policyManager == address(0)) {
            // No policy manager wired in: treat as PASS with empty attestation
            IPolicy.PolicyResult[] memory empty;
            attestation = IPolicy.ComplianceAttestation({
                envelopeHash: bytes32(0),
                overallStatus: IPolicy.PolicyStatus.Pass,
                policyResults: empty
            });
            return attestation;
        }

        IPolicyManager.TxContext memory ctx = IPolicyManager.TxContext({
            token: token,
            from: from,
            to: to,
            amount: amount,
            extraData: extraData
        });

        attestation = IPolicyManager(policyManager).runPolicies(ctx);
    }

    /// @notice Original modifier: reverts on FAIL, ignores PASS/PENDING.
    /// @dev Kept for backwards-compatibility; wrappers can now prefer _runPolicies.
    modifier runPolicy(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory extraData
    ) {
        if (policyManager != address(0)) {
            IPolicy.ComplianceAttestation memory complianceAttestation =
                _runPolicies(token, from, to, amount, extraData);

            if (complianceAttestation.overallStatus == IPolicy.PolicyStatus.Fail) {
                revert("PolicyProtected: policy check failed");
            }
        }
        _;
    }
}
