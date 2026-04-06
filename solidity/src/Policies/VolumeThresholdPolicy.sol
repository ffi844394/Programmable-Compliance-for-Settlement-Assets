// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPolicy.sol";

contract VolumeThresholdPolicy is IPolicy {
    // --- Policy identity ---

    bytes32 public constant POLICY_ID = keccak256("VolumeThresholdPolicy");
    uint64  public constant POLICY_VERSION = 1;

    // --- Configurable thresholds ---

    uint256 public lowerThreshold;
    uint256 public upperThreshold;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "VolumeThresholodPolicy: not owner");
        _;
    }

    constructor(uint256 _lower, uint256 _upper) {
        require(_lower < _upper, "VolumeThresholdPolicy: invalid thresholds");
        lowerThreshold = _lower;
        upperThreshold = _upper;
        owner = msg.sender;
    }

    // --- Policy metadata ---

    function policyId() external pure override returns (bytes32) {
        return POLICY_ID;
    }

    function policyVersion() external pure override returns (uint64) {
        return POLICY_VERSION;
    }

    // --- Admin functions ---

    function setThresholds(uint256 _lower, uint256 _upper)
        external
        onlyOwner
    {
        require(_lower < _upper, "VolumeThresholdPolicy: invalid thresholds");
        lowerThreshold = _lower;
        upperThreshold = _upper;
    }

    // --- Evaluation logic ---

    function evaluate(
        TransactionEnvelope calldata envelope
    ) external view override returns (PolicyStatus status, bytes memory proof) {
        uint256 value = envelope.amount;

        if (value > upperThreshold) {
            status = PolicyStatus.Fail;
        } else if (value > lowerThreshold) {
            status = PolicyStatus.Pending;
        } else {
            status = PolicyStatus.Pass;
        }

        // Example attestation proof: thresholds + value used
        proof = abi.encode(
            POLICY_ID,
            POLICY_VERSION,
            value,
            lowerThreshold,
            upperThreshold
        );
    }
}
