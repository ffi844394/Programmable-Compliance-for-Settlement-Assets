// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Ecosystem-wide administrative controls (Option A).
///         - Global pause shared across ABT + all wrappers that point to this.
///         - Authorized wrappers registry per token (multi-wrapper support).
///         - Recovery authority gate (clawback/forced transfer).
interface IAdminControls {
    // ---- Global pause ----
    function isSystemPaused() external view returns (bool);

    // ---- Multi-wrapper registry ----
    function isAuthorizedWrapper(address token, address wrapper) external view returns (bool);

    // ---- Recovery authority gate ----
    function canRecover(address caller) external view returns (bool);
}
