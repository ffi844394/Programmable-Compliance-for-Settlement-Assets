// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import "../src/AdministrativeControls/AdminControls.sol";
import "../src/AssetBackedToken.sol";
import "../src/PolicyWrapper/PolicyWrapper.sol";
import "../src/PolicyManager/PolicyManager.sol";
import "../src/IdentityManager/IdentityRegistry.sol";
import "../src/Policies/KYCPolicy.sol";
import "../src/Policies/VolumeThresholdPolicy.sol";

contract AdminControlsIntegrationTest is Test {
    // Core system
    AdminControls public adminControls;
    AssetBackedToken public abt;
    PolicyWrapper public wrapper;
    PolicyManager public policyManager;
    IdentityRegistry public idRegistry;
    KYCPolicy public kycPolicy;
    VolumeThresholdPolicy public volumePolicy;

    // Actors
    address public governor;
    address public registrar;
    address public recoveryOps;
    address public issuer;
    address public wrapperOperator;
    address public identityProvider;

    address public alice;
    address public bob;

    // Simple thresholds for the volume policy
    uint256 public constant LOWER_THRESHOLD = 100;
    uint256 public constant UPPER_THRESHOLD = 200;

    function setUp() public {
        governor        = makeAddr("governor");
        registrar       = makeAddr("registristrar");
        recoveryOps     = makeAddr("recoveryOps");
        issuer          = makeAddr("issuer");
        wrapperOperator = makeAddr("wrapperOperator");
        identityProvider = makeAddr("identityProvider");

        alice = makeAddr("alice");
        bob   = makeAddr("bob");

        // -------- Deploy AdminControls --------
        vm.prank(governor);
        adminControls = new AdminControls(governor, registrar, recoveryOps);

        // -------- Identity registry --------
        vm.prank(identityProvider);
        idRegistry = new IdentityRegistry();

        // -------- PolicyManager --------
        policyManager = new PolicyManager(governor, address(idRegistry));

        // -------- Deploy ABT --------
        vm.prank(issuer);
        abt = new AssetBackedToken(
            "TestABT",
            "TABT",
            "https://example.com/uri",
            issuer,
            address(adminControls)
        );

        // -------- Deploy Wrapper --------
        vm.prank(wrapperOperator);
        wrapper = new PolicyWrapper(
            wrapperOperator,
            address(abt),
            1 days,
            "WrappedTABT",
            "wTABT",
            address(policyManager),
            address(adminControls)
        );

        // -------- Authorize wrapper at AdminControls (issuer/registrar does this) --------
        vm.prank(registrar);
        adminControls.authorizeWrapper(address(abt), address(wrapper), true);

        // -------- Register wrapper as policy runner --------
        vm.prank(governor);
        policyManager.setRunner(address(wrapper), true);

        // -------- Policies --------
        vm.startPrank(governor);

        volumePolicy = new VolumeThresholdPolicy(LOWER_THRESHOLD, UPPER_THRESHOLD);
        policyManager.addPolicy(address(volumePolicy));

        kycPolicy = new KYCPolicy(
            1,
            true,  // requireOriginatorCustomerKyc
            true,  // requireBeneficiaryCustomerKyc
            false  // requireVaspKyc
        );
        policyManager.addPolicy(address(kycPolicy));

        vm.stopPrank();

        // -------- KYC identities (identity provider) --------
        vm.startPrank(identityProvider);
        idRegistry.setIdentity(
            alice,
            keccak256("ALICE_ID"),
            keccak256("ALICE_KYC")
        );
        idRegistry.setIdentity(
            bob,
            keccak256("BOB_ID"),
            keccak256("BOB_KYC")
        );
        vm.stopPrank();

        // -------- Mint ABT to Alice (issuer) --------
        vm.prank(issuer);
        abt.mint(alice, 1_000_000); // raw units, decimals don't matter for the test

        // -------- Baseline: Alice wraps some tokens successfully --------
        vm.startPrank(alice);
        abt.approve(address(wrapper), 1000);
        wrapper.depositFor(alice, 1000);
        vm.stopPrank();
    }

    // ------------------------------------------------------------
    // 1. Global pause → enforced in ABT + Wrapper
    // ------------------------------------------------------------

    function testPauseBlocksDirectABTTransfer() public {
        // Pause system
        vm.prank(governor);
        adminControls.pause();

        // Attempt ABT transfer → must revert due to global pause
        vm.prank(alice);
        vm.expectRevert("ABT: paused");
        abt.transfer(bob, 10);
    }

    function testPauseBlocksWrapperDeposit() public {
        // Pause system
        vm.prank(governor);
        adminControls.pause();

        // Alice tries to wrap more ABT
        vm.startPrank(alice);
        abt.approve(address(wrapper), 10);

        vm.expectRevert("PolicyWrapper: system paused");
        wrapper.depositFor(alice, 10);

        vm.stopPrank();
    }

    function testPauseBlocksWrapperTransfer() public {
        // Pause system
        vm.prank(governor);
        adminControls.pause();

        // Alice already has wrapped balance from setUp
        vm.prank(alice);
        vm.expectRevert("PolicyWrapper: system paused");
        wrapper.transfer(bob, 5);
    }

    function testUnpauseRestoresWrapperTransfer() public {
        // Pause
        vm.prank(governor);
        adminControls.pause();

        // Unpause
        vm.prank(governor);
        adminControls.unpause();

        // Transfer should now succeed (KYC & policy ok, not focusing on volume here)
        vm.prank(alice);
        wrapper.transfer(bob, 5);

        assertEq(wrapper.balanceOf(bob), 5, "Bob should receive wrapped tokens after unpause");
    }

    // ------------------------------------------------------------
    // 2. Wrapper allowlist → enforced via ABT
    // ------------------------------------------------------------

    function testDeauthorizingWrapperBlocksNewWrapping() public {
        // Baseline: deposit works now — do one extra deposit
        vm.startPrank(alice);
        abt.approve(address(wrapper), 100);
        wrapper.depositFor(alice, 100); // should work (wrapper is currently authorized)
        vm.stopPrank();

        uint256 wrappedBefore = wrapper.balanceOf(alice);

        // De-authorize wrapper for this token (registrar or governor can do this)
        vm.prank(registrar);
        adminControls.authorizeWrapper(address(abt), address(wrapper), false);

        // Alice attempts another deposit → should fail at ABT level
        vm.startPrank(alice);
        abt.approve(address(wrapper), 50);
        vm.expectRevert("ABT: transfers restricted");
        wrapper.depositFor(alice, 50);
        vm.stopPrank();

        // Wrapped balance should remain unchanged
        uint256 wrappedAfter = wrapper.balanceOf(alice);
        assertEq(wrappedAfter, wrappedBefore, "Wrapped balance should not increase after deauth");
    }

    // ------------------------------------------------------------
    // 3. Recovery authority → enforced via AdminControls.canRecover
    // ------------------------------------------------------------

    function testRecoveryOnlyByRecoveryAuthority() public {
        // Give Bob some ABT initially so we can see movement clearly
        vm.prank(issuer);
        abt.mint(bob, 500);

        uint256 aliceBefore = abt.balanceOf(alice);
        uint256 bobBefore   = abt.balanceOf(bob);

        // 1. Random user cannot recover
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert("ABT: not recovery admin");
        abt.recover(alice, bob, 100);

        assertEq(abt.balanceOf(alice), aliceBefore, "Alice balance must not change (stranger)");
        assertEq(abt.balanceOf(bob),   bobBefore,   "Bob balance must not change (stranger)");

        // 2. RecoveryOps can recover
        vm.prank(recoveryOps);
        abt.recover(alice, bob, 100);

        assertEq(
            abt.balanceOf(alice),
            aliceBefore - 100,
            "Alice balance should decrease after recovery"
        );
        assertEq(
            abt.balanceOf(bob),
            bobBefore + 100,
            "Bob balance should increase after recovery"
        );
    }

    function testRecoveryBlockedWhenSystemPaused() public {
        uint256 aliceBefore = abt.balanceOf(alice);
        uint256 bobBefore   = abt.balanceOf(bob);

        // Pause system
        vm.prank(governor);
        adminControls.pause();

        // Even recoveryOps should fail if ABT._update still checks pause
        vm.prank(recoveryOps);
        vm.expectRevert("ABT: paused");
        abt.recover(alice, bob, 50);

        assertEq(abt.balanceOf(alice), aliceBefore, "Alice balance should remain unchanged");
        assertEq(abt.balanceOf(bob),   bobBefore,   "Bob balance should remain unchanged");
    }

    // ------------------------------------------------------------
    // 4. Role rotation → prove that new roles drive controls in ABT/Wrapper
    // ------------------------------------------------------------

    function testRoleRotationAffectsPauseAndAllowlist() public {
        // New role holders
        address newGovernor  = makeAddr("newGovernor");
        address newRegistrar = makeAddr("newRegistrar");
        address newRecovery  = makeAddr("newRecovery");

        // Rotate roles (only old governor can do this)
        vm.prank(governor);
        adminControls.setRoles(newGovernor, newRegistrar, newRecovery);

        // ---- Old governor loses pause power ----
        vm.prank(governor);
        vm.expectRevert("AdminControls: not governor");
        adminControls.pause();

        // ---- New governor can pause ----
        vm.prank(newGovernor);
        adminControls.pause();
        assertTrue(adminControls.isSystemPaused(), "System should be paused by new governor");

        // While paused, wrapper transfer should fail
        vm.prank(alice);
        vm.expectRevert("PolicyWrapper: system paused");
        wrapper.transfer(bob, 10);

        // Unpause by new governor
        vm.prank(newGovernor);
        adminControls.unpause();
        assertFalse(adminControls.isSystemPaused(), "System should be unpaused by new governor");

        // ---- Old registrar loses allowlist power ----
        vm.prank(registrar);
        vm.expectRevert("AdminControls: not registrar/governor");
        adminControls.authorizeWrapper(address(abt), address(wrapper), false);

        // ---- New registrar can de-authorize wrapper ----
        vm.prank(newRegistrar);
        adminControls.authorizeWrapper(address(abt), address(wrapper), false);

        // Now wrapping should fail because wrapper is no longer authorized
        vm.startPrank(alice);
        abt.approve(address(wrapper), 10);
        vm.expectRevert("ABT: transfers restricted");
        wrapper.depositFor(alice, 10);
        vm.stopPrank();

        // ---- New recoveryOps can recover ----
        uint256 aliceBefore = abt.balanceOf(alice);
        uint256 bobBefore   = abt.balanceOf(bob);

        vm.prank(newRecovery);
        abt.recover(alice, bob, 5);

        assertEq(abt.balanceOf(alice), aliceBefore - 5, "Alice balance should drop by 5 after newRecovery");
        assertEq(abt.balanceOf(bob),   bobBefore + 5,   "Bob balance should increase by 5 after newRecovery");
    }
}
