// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../AdministrativeControls/IAdminControls.sol";
import "./PolicyProtected.sol";
import "../interfaces/IPolicy.sol";

contract PolicyWrapper is ERC20Wrapper, Ownable, Pausable, PolicyProtected {
    // ---------------------------------------------------------------------
    // AdminControls (ecosystem-wide pause + wrapper registry)
    // ---------------------------------------------------------------------
    IAdminControls public adminControls;

    modifier whenSystemNotPaused() {
        require(address(adminControls) != address(0), "PolicyWrapper: adminControls not set");
        require(!adminControls.isSystemPaused(), "PolicyWrapper: system paused");
        _;
    }

    event AdminControlsUpdated(address indexed sender, address indexed oldAdmin, address indexed newAdmin);
    event TimeoutUpdated(address indexed sender, uint256 oldTimeout, uint256 newTimeout);

    // ---------------------------------------------------------------------
    // Types / storage
    // ---------------------------------------------------------------------
    uint256 public timeoutReject;
    uint256 private _txIdCount;

    enum Status { Unknown, Pending, Accepted, Rejected }

    struct TxData {
        address from;
        address to;
        uint256 amount;
        Status  status;
        uint256 timeout;       // only meaningful once Accepted
        bytes32 envelopeHash;  // compliance envelope hash from PolicyManager
    }

    mapping(uint256 => TxData) private _txIdToData;

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    constructor(
        address initialOwner,
        address sovToken,
        uint256 timeoutReject_,
        string memory name_,
        string memory symbol_,
        address policyManager_,
        address adminControls_
    )
        ERC20(name_, symbol_)
        ERC20Wrapper(IERC20(sovToken))
        Ownable(initialOwner)
    {
        require(initialOwner != address(0), "PolicyWrapper: owner is zero");
        require(sovToken != address(0), "PolicyWrapper: token is zero");
        require(policyManager_ != address(0), "PolicyWrapper: manager is zero");
        require(adminControls_ != address(0), "PolicyWrapper: adminControls is zero");

        timeoutReject = timeoutReject_;
        adminControls = IAdminControls(adminControls_);
        emit AdminControlsUpdated(msg.sender, address(0), adminControls_);

        __PolicyProtected_init(policyManager_);
    }

    // ---------------------------------------------------------------------
    // Admin (local ops stay here)
    // ---------------------------------------------------------------------
    function setAdminControls(address newAdminControls) external onlyOwner {
        require(newAdminControls != address(0), "PolicyWrapper: adminControls is zero");
        emit AdminControlsUpdated(msg.sender, address(adminControls), newAdminControls);
        adminControls = IAdminControls(newAdminControls);
    }

    function updateTimeout(uint256 timeoutReject_) external onlyOwner {
        emit TimeoutUpdated(msg.sender, timeoutReject, timeoutReject_);
        timeoutReject = timeoutReject_;
    }

    function updatePolicyManager(address policyManager_) external onlyOwner {
        _setPolicyManager(policyManager_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // User functions
    // ---------------------------------------------------------------------

    function rejectTx(uint256 id) external whenSystemNotPaused whenNotPaused {
        TxData storage txData = _txIdToData[id];

        require(txData.to == msg.sender, "PolicyWrapper: invalid sender");
        require(txData.status == Status.Accepted, "PolicyWrapper: tx not Accepted");
        require(txData.timeout >= block.timestamp, "PolicyWrapper: timeout expired");

        txData.status = Status.Rejected;

        // Reverse transfer back to sender.
        super.transfer(txData.from, txData.amount);
    }

    function depositFor(address to, uint256 amount)
        public
        override(ERC20Wrapper)
        whenSystemNotPaused
        whenNotPaused
        returns (bool)
    {
        super.depositFor(to, amount);
        return true;
    }

    function withdrawTo(address to, uint256 amount)
        public
        override(ERC20Wrapper)
        whenSystemNotPaused
        whenNotPaused
        returns (bool)
    {
        super.withdrawTo(to, amount);
        return true;
    }

    function transfer(address to, uint256 value)
        public
        override(ERC20)
        whenSystemNotPaused
        whenNotPaused
        returns (bool)
    {
        IPolicy.ComplianceAttestation memory att =
            _runPolicies(address(underlying()), msg.sender, to, value, "");

        if (att.overallStatus == IPolicy.PolicyStatus.Fail) {
            revert("PolicyProtected: policy check failed");
        }

        Status initialStatus;
        uint256 timeout;

        if (att.overallStatus == IPolicy.PolicyStatus.Pass) {
            initialStatus = Status.Accepted;
            timeout = block.timestamp + timeoutReject;
        } else {
            initialStatus = Status.Pending;
            timeout = 0;
        }

        uint256 txId = _registerTx(msg.sender, to, value, initialStatus, timeout, att.envelopeHash);

        if (att.overallStatus == IPolicy.PolicyStatus.Pass) {
            super.transfer(to, value);
        } else {
            txId; // placeholder (you may emit events later)
        }

        return true;
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC20)
        whenSystemNotPaused
        whenNotPaused
        returns (bool)
    {
        IPolicy.ComplianceAttestation memory att =
            _runPolicies(address(underlying()), from, to, value, "");

        if (att.overallStatus == IPolicy.PolicyStatus.Fail) {
            revert("PolicyProtected: policy check failed");
        }

        Status initialStatus;
        uint256 timeout;

        if (att.overallStatus == IPolicy.PolicyStatus.Pass) {
            initialStatus = Status.Accepted;
            timeout = block.timestamp + timeoutReject;
        } else {
            initialStatus = Status.Pending;
            timeout = 0;
        }

        uint256 txId = _registerTx(from, to, value, initialStatus, timeout, att.envelopeHash);

        if (att.overallStatus == IPolicy.PolicyStatus.Pass) {
            super.transferFrom(from, to, value);
        } else {
            txId;
        }

        return true;
    }

    // ---------------------------------------------------------------------
    // Pending execution (wrapper-operator controlled)
    // ---------------------------------------------------------------------
    function executePendingTx(uint256 id)
        external
        whenSystemNotPaused
        whenNotPaused
        onlyOwner
        returns (bool)
    {
        TxData storage txData = _txIdToData[id];

        require(txData.amount > 0, "PolicyWrapper: unknown tx");
        require(txData.status == Status.Pending, "PolicyWrapper: tx not pending");

        IPolicy.ComplianceAttestation memory att =
            _runPolicies(address(underlying()), txData.from, txData.to, txData.amount, "");

        require(att.overallStatus == IPolicy.PolicyStatus.Pass, "PolicyWrapper: still not compliant");

        txData.status = Status.Accepted;
        txData.timeout = block.timestamp + timeoutReject;
        txData.envelopeHash = att.envelopeHash;

        // Move wrapped tokens without re-triggering policy checks.
        super._transfer(txData.from, txData.to, txData.amount);

        return true;
    }

    // ---------------------------------------------------------------------
    // View helpers
    // ---------------------------------------------------------------------
    function getTxData(uint256 id) external view returns (TxData memory) {
        return _txIdToData[id];
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------
    function _registerTx(
        address from,
        address to,
        uint256 amount,
        Status status,
        uint256 timeout,
        bytes32 envelopeHash
    ) private returns (uint256) {
        uint256 currentId = _txIdCount;
        _txIdCount++;

        _txIdToData[currentId] = TxData({
            from: from,
            to: to,
            amount: amount,
            status: status,
            timeout: timeout,
            envelopeHash: envelopeHash
        });

        return currentId;
    }
}
