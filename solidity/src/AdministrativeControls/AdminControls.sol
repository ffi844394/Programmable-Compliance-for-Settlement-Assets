// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IAdminControls.sol";

/// @notice AdminControls (Option A)
///         - One shared global pause for all modules wired to this AdminControls.
///         - Wrapper allowlist keyed by token address (ABT) => wrapper address.
///         - Recovery authority gate.
/// @dev Keep this small and auditable. Per-contract operational actions remain in each contract's Ownable.
contract AdminControls is IAdminControls {
    // -------------------------
    // Roles (keep these as multisigs / timelocks in production)
    // -------------------------
    address public governor;      // can pause/unpause, manage wrapper allowlist, rotate roles
    address public registrar;     // optional: can manage wrapper allowlist (e.g., issuer ops multisig)
    address public recoveryOps;   // can perform recovery

    bool private _paused;

    // token => wrapper => allowed
    mapping(address => mapping(address => bool)) private _authorizedWrappers;

    // -------------------------
    // Events
    // -------------------------
    event Paused(address indexed caller);
    event Unpaused(address indexed caller);

    event RolesUpdated(
        address indexed governor,
        address indexed registrar,
        address indexed recoveryOps
    );

    event WrapperAuthorizationUpdated(
        address indexed caller,
        address indexed token,
        address indexed wrapper,
        bool allowed
    );

    // -------------------------
    // Modifiers
    // -------------------------
    modifier onlyGovernor() {
        require(msg.sender == governor, "AdminControls: not governor");
        _;
    }

    modifier onlyRegistrarOrGovernor() {
        require(msg.sender == governor || msg.sender == registrar, "AdminControls: not registrar/governor");
        _;
    }

    constructor(address governor_, address registrar_, address recoveryOps_) {
        require(governor_ != address(0), "AdminControls: governor is zero");
        governor = governor_;
        registrar = registrar_;
        recoveryOps = recoveryOps_;
        emit RolesUpdated(governor, registrar, recoveryOps);
    }

    // -------------------------
    // Global pause
    // -------------------------
    function isSystemPaused() external view returns (bool) {
        return _paused;
    }

    function pause() external onlyGovernor {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyGovernor {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    // -------------------------
    // Wrapper allowlist (multi-wrapper support)
    // -------------------------
    function isAuthorizedWrapper(address token, address wrapper) external view returns (bool) {
        return _authorizedWrappers[token][wrapper];
    }

    function authorizeWrapper(address token, address wrapper, bool allowed)
        external
        onlyRegistrarOrGovernor
    {
        require(token != address(0), "AdminControls: token is zero");
        require(wrapper != address(0), "AdminControls: wrapper is zero");

        _authorizedWrappers[token][wrapper] = allowed;
        emit WrapperAuthorizationUpdated(msg.sender, token, wrapper, allowed);
    }

    // -------------------------
    // Recovery authority gate
    // -------------------------
    function canRecover(address caller) external view returns (bool) {
        return caller == governor || (recoveryOps != address(0) && caller == recoveryOps);
    }

    // -------------------------
    // Role management
    // -------------------------
    function setRoles(address governor_, address registrar_, address recoveryOps_) external onlyGovernor {
        require(governor_ != address(0), "AdminControls: governor is zero");
        governor = governor_;
        registrar = registrar_;
        recoveryOps = recoveryOps_;
        emit RolesUpdated(governor, registrar, recoveryOps);
    }
}
