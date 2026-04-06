// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import "../src/AdministrativeControls/AdminControls.sol";
import "../src/AssetBackedToken.sol";
import "../src/PolicyWrapper/PolicyWrapper.sol";
import "../src/PolicyManager/PolicyManager.sol";
import "../src/IdentityManager/IdentityRegistry.sol";
import "../src/Policies/VolumeThresholdPolicy.sol";

contract MultiWrapperTransactionTest is Test {
    // Core contracts
    AdminControls public adminControls;
    AssetBackedToken public abt;

    // Shared identity registry (optional for VolumeThresholdPolicy, but PolicyManager expects it)
    IdentityRegistry public identityRegistry;

    // Wrapper A stack
    PolicyWrapper public wrapperA;
    PolicyManager public policyManagerA;
    VolumeThresholdPolicy public volumePolicyA;

    // Wrapper B stack
    PolicyWrapper public wrapperB;
    PolicyManager public policyManagerB;
    VolumeThresholdPolicy public volumePolicyB;

    // Roles
    address public issuer;
    address public complianceAdminA;
    address public complianceAdminB;
    address public identityProvider;

    address public vaspOperatorA;
    address public vaspOperatorB;

    // Retail users
    address public alice;
    address public bob;

    // Threshold sets (chosen to avoid "Pending" ambiguity by using values <= lower for PASS and > upper for FAIL)
    // If your VolumeThresholdPolicy behaves like:
    //   value <= lower  => PASS
    //   lower < value <= upper => PENDING
    //   value > upper => FAIL
    // then these tests will behave deterministically.
    uint256 public constant A_LOWER = 100;
    uint256 public constant A_UPPER = 200;

    uint256 public constant B_LOWER = 300;
    uint256 public constant B_UPPER = 500;

    function setUp() public {
        // --- Actors ---
        issuer = makeAddr("issuer");
        identityProvider = makeAddr("identityProvider");

        complianceAdminA = makeAddr("complianceAdminA");
        complianceAdminB = makeAddr("complianceAdminB");

        vaspOperatorA = makeAddr("vaspOperatorA");
        vaspOperatorB = makeAddr("vaspOperatorB");

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // --- Deploy AdminControls ---
        // PoC: issuer is governor + registrar + recoveryOps
        vm.prank(issuer);
        adminControls = new AdminControls(issuer, issuer, issuer);

        // --- Deploy IdentityRegistry (owned by identity provider) ---
        vm.prank(identityProvider);
        identityRegistry = new IdentityRegistry();

        // --- Deploy ABT (owned by issuer) ---
        vm.prank(issuer);
        abt = new AssetBackedToken(
            "Test Asset Backed Token",
            "TABT",
            "https://example.com/supplemental.json",
            issuer,
            address(adminControls)
        );

        // --- Deploy PolicyManagers (different compliance admins) ---
        policyManagerA = new PolicyManager(complianceAdminA, address(identityRegistry));
        policyManagerB = new PolicyManager(complianceAdminB, address(identityRegistry));

        // --- Deploy Wrappers (different operators) ---
        vm.prank(vaspOperatorA);
        wrapperA = new PolicyWrapper(
            vaspOperatorA,
            address(abt),
            1 days,
            "Wrapped TABT A",
            "wTABT-A",
            address(policyManagerA),
            address(adminControls)
        );

        vm.prank(vaspOperatorB);
        wrapperB = new PolicyWrapper(
            vaspOperatorB,
            address(abt),
            1 days,
            "Wrapped TABT B",
            "wTABT-B",
            address(policyManagerB),
            address(adminControls)
        );

        // --- Authorize BOTH wrappers for the SAME ABT ---
        vm.startPrank(issuer);
        adminControls.authorizeWrapper(address(abt), address(wrapperA), true);
        adminControls.authorizeWrapper(address(abt), address(wrapperB), true);
        vm.stopPrank();

        // --- Allow wrappers to run policies (per-policy-manager) ---
        vm.prank(complianceAdminA);
        policyManagerA.setRunner(address(wrapperA), true);

        vm.prank(complianceAdminB);
        policyManagerB.setRunner(address(wrapperB), true);

        // --- Deploy & register different VolumeThresholdPolicies ---
        vm.prank(complianceAdminA);
        volumePolicyA = new VolumeThresholdPolicy(A_LOWER, A_UPPER);
        vm.prank(complianceAdminA);
        policyManagerA.addPolicy(address(volumePolicyA));

        vm.prank(complianceAdminB);
        volumePolicyB = new VolumeThresholdPolicy(B_LOWER, B_UPPER);
        vm.prank(complianceAdminB);
        policyManagerB.addPolicy(address(volumePolicyB));

        // --- Mint underlying TABT to Alice ---
        vm.prank(issuer);
        abt.mint(alice, 10_000);
    }

    function testDeploymentAndAuthorizationForBothWrappers() public view {
        // Same ABT uses the same AdminControls
        assertEq(address(abt.adminControls()), address(adminControls), "ABT adminControls mismatch");

        // Both wrappers use same AdminControls
        assertEq(address(wrapperA.adminControls()), address(adminControls), "WrapperA adminControls mismatch");
        assertEq(address(wrapperB.adminControls()), address(adminControls), "WrapperB adminControls mismatch");

        // Both wrappers are authorized for the same ABT
        assertTrue(adminControls.isAuthorizedWrapper(address(abt), address(wrapperA)), "WrapperA not authorized");
        assertTrue(adminControls.isAuthorizedWrapper(address(abt), address(wrapperB)), "WrapperB not authorized");

        // Each wrapper is runner only in its own policy manager
        assertTrue(policyManagerA.isRunner(address(wrapperA)), "WrapperA not runner in PM-A");
        assertTrue(policyManagerB.isRunner(address(wrapperB)), "WrapperB not runner in PM-B");
    }

    function testConcurrentTransfersDifferentRulesApply() public {
        // --- Deposit into BOTH wrappers (Alice can use both rails concurrently) ---
        vm.startPrank(alice);

        // Wrap 400 into wrapperA
        abt.approve(address(wrapperA), 400);
        wrapperA.depositFor(alice, 400);

        // Wrap 700 into wrapperB
        abt.approve(address(wrapperB), 700);
        wrapperB.depositFor(alice, 700);

        // --- PASS case on wrapperA: transfer 50 (<= A_LOWER=100) should PASS and execute
        wrapperA.transfer(bob, 50);

        // --- PASS case on wrapperB: transfer 250 (<= B_LOWER=300) should PASS and execute
        wrapperB.transfer(bob, 250);

        vm.stopPrank();

        // Balances are independent (two different wrapped tokens)
        assertEq(wrapperA.balanceOf(bob), 50, "Bob should have 50 wTABT-A");
        assertEq(wrapperB.balanceOf(bob), 250, "Bob should have 250 wTABT-B");

        // And Alice’s balances reflect each wrapper separately
        assertEq(wrapperA.balanceOf(alice), 400 - 50, "Alice wTABT-A balance incorrect");
        assertEq(wrapperB.balanceOf(alice), 700 - 250, "Alice wTABT-B balance incorrect");
    }

    function testWrapperARejectsButWrapperBAllowsSameAmount() public {
        // For A: 250 > A_UPPER(200) => FAIL (revert)
        // For B: 250 <= B_LOWER(300) => PASS

        // Deposit enough into both wrappers first
        vm.startPrank(alice);
        abt.approve(address(wrapperA), 300);
        wrapperA.depositFor(alice, 300);

        abt.approve(address(wrapperB), 300);
        wrapperB.depositFor(alice, 300);

        // wrapperB should allow 250
        wrapperB.transfer(bob, 250);
        assertEq(wrapperB.balanceOf(bob), 250, "Bob should receive 250 on wrapperB");

        // wrapperA should reject 250
        vm.expectRevert(); // underlying revert reason may differ by your PolicyProtected/PolicyWrapper
        wrapperA.transfer(bob, 250);

        vm.stopPrank();

        // Ensure wrapperA did NOT transfer
        assertEq(wrapperA.balanceOf(bob), 0, "Bob should not receive tokens on wrapperA");
    }

    function testBothWrappersFailIndependently() public {
        // A fails for 250 (>200)
        // B fails for 600 (>500)
        vm.startPrank(alice);

        abt.approve(address(wrapperA), 300);
        wrapperA.depositFor(alice, 300);

        abt.approve(address(wrapperB), 700);
        wrapperB.depositFor(alice, 700);

        vm.expectRevert();
        wrapperA.transfer(bob, 250);

        vm.expectRevert();
        wrapperB.transfer(bob, 600);

        vm.stopPrank();

        assertEq(wrapperA.balanceOf(bob), 0, "Bob should have 0 wTABT-A after A failure");
        assertEq(wrapperB.balanceOf(bob), 0, "Bob should have 0 wTABT-B after B failure");
    }
}
