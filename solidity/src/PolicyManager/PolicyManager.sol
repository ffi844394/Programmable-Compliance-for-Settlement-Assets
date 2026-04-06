// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPolicy.sol";
import "../interfaces/IPolicyManager.sol";
import "../IdentityManager/IdentityRegistry.sol";

contract PolicyManager is IPolicyManager {
    // --- Events ---

    event PolicyAdded(address policy);
    event PolicyRemoved(address policy);
    event PolicyOverrideSet(address policy, IPolicy.PolicyStatus status);

    event PoliciesRun(
        address indexed caller,
        bytes32 indexed envelopeHash,
        IPolicy.PolicyStatus overallStatus
    );

    event IdentityRegistryUpdated(
        address indexed sender,
        address indexed oldRegistry,
        address indexed newRegistry
    );

    // --- Storage ---

    address[] public policies;
    mapping(address => bool) public isPolicy;

    // Manual overrides for policies that report Pending
    mapping(address => IPolicy.PolicyStatus) public manualOverrideStatus;

    // Simple access control
    address public owner;
    mapping(address => bool) public isRunner;

    // Identity registry used to hydrate IdentityPackets
    address public identityRegistry;

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == owner, "PolicyManager: not owner");
        _;
    }

    modifier onlyRunner() {
        require(
            msg.sender == owner || isRunner[msg.sender],
            "PolicyManager: not authorized"
        );
        _;
    }

    // --- Constructor ---

    constructor(address _owner, address _identityRegistry) {
        require(_owner != address(0), "PolicyManager: owner is zero");
        owner = _owner;

        if (_identityRegistry != address(0)) {
            identityRegistry = _identityRegistry;
            emit IdentityRegistryUpdated(msg.sender, address(0), _identityRegistry);
        }
    }

    // --- Owner / runner management ---

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PolicyManager: owner is zero");
        owner = newOwner;
    }

    function setRunner(address runner, bool allowed) external onlyOwner {
        require(runner != address(0), "PolicyManager: runner is zero");
        isRunner[runner] = allowed;
    }

    // --- Identity registry management ---

    function setIdentityRegistry(address registry) external onlyOwner {
        require(registry != address(0), "PolicyManager: registry is zero");
        emit IdentityRegistryUpdated(msg.sender, identityRegistry, registry);
        identityRegistry = registry;
    }

    // --- Policy management ---

    function addPolicy(address policy) external onlyOwner {
        require(policy != address(0), "PolicyManager: policy is zero");
        require(!isPolicy[policy], "PolicyManager: already added");

        policies.push(policy);
        isPolicy[policy] = true;

        emit PolicyAdded(policy);
    }

    function removePolicy(address policy) external onlyOwner {
        require(isPolicy[policy], "PolicyManager: not a policy");

        uint256 len = policies.length;
        for (uint256 i = 0; i < len; i++) {
            if (policies[i] == policy) {
                if (i != len - 1) {
                    policies[i] = policies[len - 1];
                }
                policies.pop();
                break;
            }
        }

        isPolicy[policy] = false;
        manualOverrideStatus[policy] = IPolicy.PolicyStatus.Unknown;

        emit PolicyRemoved(policy);
    }

    function getPolicies() external view returns (address[] memory) {
        return policies;
    }

    // --- Manual resolution of pending policies ---

    function resolvePending(address policy, bool pass) external onlyRunner {
        require(isPolicy[policy], "PolicyManager: not a policy");

        IPolicy.PolicyStatus newStatus = pass
            ? IPolicy.PolicyStatus.Pass
            : IPolicy.PolicyStatus.Fail;

        manualOverrideStatus[policy] = newStatus;
        emit PolicyOverrideSet(policy, newStatus);
    }

    // --- Run policies over a TxContext (build envelope + attestation) ---
    function runPolicies(
        TxContext calldata ctx
    )
        external
        onlyRunner
        override
        returns (IPolicy.ComplianceAttestation memory attestation)
    {
        uint256 len = policies.length;

        // 1) Build PartyPackets for originator and beneficiary.
        // Will need to refactor this to handle dynamic parties in the future

        IPolicy.PartyPacket memory originator;
        IPolicy.PartyPacket memory beneficiary;
        IPolicy.PartyPacket[] memory parties = new IPolicy.PartyPacket[](2);

        originator.role = IPolicy.PartyRole.OriginatorCustomer;
        originator.wallet = ctx.from;

        beneficiary.role = IPolicy.PartyRole.BeneficiaryCustomer;
        beneficiary.wallet = ctx.to;

        if (identityRegistry != address(0)) {
            (bytes32 oRef, bytes32 oKyc) =
                IdentityRegistry(identityRegistry).getIdentity(ctx.from);
            (bytes32 bRef, bytes32 bKyc) =
                IdentityRegistry(identityRegistry).getIdentity(ctx.to);

            originator.identityRef = oRef;
            originator.kycHash = oKyc;

            beneficiary.identityRef = bRef;
            beneficiary.kycHash = bKyc;
        }

        parties[0] = originator;
        parties[1] = beneficiary;

        // 2) Build TransactionEnvelope.
        IPolicy.TransactionEnvelope memory envelope;
        envelope.token = ctx.token;
        envelope.amount = ctx.amount;
        envelope.timestamp = block.timestamp;
        envelope.extraData = ctx.extraData;
        envelope.parties = parties;

        // 3) Prepare per-policy results.
        IPolicy.PolicyResult[] memory results =
            new IPolicy.PolicyResult[](len);

        IPolicy.PolicyStatus overall = IPolicy.PolicyStatus.Pass;

        // evaluate each Policy
        for (uint256 i = 0; i < len; i++) {
            address policyAddr = policies[i];
            IPolicy policy = IPolicy(policyAddr);

            (IPolicy.PolicyStatus status, bytes memory proof) =
                policy.evaluate(envelope);

            if (status == IPolicy.PolicyStatus.Pending) {
                IPolicy.PolicyStatus overrideStatus =
                    manualOverrideStatus[policyAddr];

                if (overrideStatus == IPolicy.PolicyStatus.Pass) {
                    status = IPolicy.PolicyStatus.Pass;
                } else if (overrideStatus == IPolicy.PolicyStatus.Fail) {
                    status = IPolicy.PolicyStatus.Fail;
                } else {
                    if (overall != IPolicy.PolicyStatus.Fail) {
                        overall = IPolicy.PolicyStatus.Pending;
                    }
                }
            }

            if (status == IPolicy.PolicyStatus.Fail) {
                overall = IPolicy.PolicyStatus.Fail;
            } else if (
                status == IPolicy.PolicyStatus.Pending &&
                overall != IPolicy.PolicyStatus.Fail
            ) {
                overall = IPolicy.PolicyStatus.Pending;
            }

            results[i] = IPolicy.PolicyResult({
                policyId: policy.policyId(),
                policyVersion: policy.policyVersion(),
                status: status,
                evaluatedAt: block.timestamp,
                attestationProof: proof
            });
        }

        // 4) Build ComplianceAttestation.
        bytes32 envHash = keccak256(abi.encode(envelope));

        attestation = IPolicy.ComplianceAttestation({
            envelopeHash: envHash,
            overallStatus: overall,
            policyResults: results
        });

        emit PoliciesRun(msg.sender, envHash, overall);
    }


}
