// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/AdministrativeControls/AdminControls.sol";
import "../src/AssetBackedToken.sol";
import "../src/PolicyWrapper/PolicyWrapper.sol";
import "../src/PolicyManager/PolicyManager.sol";
import "../src/IdentityManager/IdentityRegistry.sol";
import "../src/Policies/VolumeThresholdPolicy.sol";
import "../src/Policies/KYCPolicy.sol";

contract TransactionTest is Test {
    // Core contracts
    AdminControls public adminControls;
    AssetBackedToken public abt;
    PolicyWrapper public wrapper;
    PolicyManager public policyManager;
    IdentityRegistry public identityRegistry;
    VolumeThresholdPolicy public volumeThresholdPolicy;
    KYCPolicy public kycPolicy;

    // --- Segregated roles ---
    address public issuer;           // TABT issuer / token contract owner
    address public vaspOperator;     // operator of the wrapper (custodian / VASP)
    address public complianceAdmin;  // PolicyManager owner + policy deployer
    address public identityProvider; // operator of IdentityRegistry (KYC utility / IDP)

    // Retail users
    address public alice;
    address public bob;
    address public charlie;

    // Example thresholds for VolumeThresholdPolicy
    uint256 public constant LOWER_THRESHOLD = 100;
    uint256 public constant UPPER_THRESHOLD = 200;

    function setUp() public {
        // --- Actors ---
        issuer = makeAddr("issuer");
        vaspOperator = makeAddr("vaspOperator");
        complianceAdmin = makeAddr("complianceAdmin");
        identityProvider = makeAddr("identityProvider");

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // --- Deploy AdminControls ---
        // For POC, issuer is the governor+registrar+recoveryOps
        vm.prank(issuer);
        adminControls = new AdminControls(
            issuer, // governor
            issuer, // registrar
            issuer  // recoveryOps
        );

        // --- Deploy IdentityRegistry (owned by Identity Provider) ---
        vm.prank(identityProvider);
        identityRegistry = new IdentityRegistry();

        // --- Deploy PolicyManager (owned by Compliance Admin) ---
        policyManager = new PolicyManager(complianceAdmin, address(identityRegistry));

        // --- Deploy TABT (owned by Issuer), wired to AdminControls ---
        vm.prank(issuer);
        abt = new AssetBackedToken(
            "Test Asset Backed Token",               // name_
            "TABT",                                  // symbol_
            "https://example.com/supplemental.json", // supplementalInformationUriValue
            issuer,                                  // initialOwner
            address(adminControls)                   // adminControls_
        );

        // --- Deploy PolicyWrapper (owned/operated by VASP Operator), wired to AdminControls ---
        vm.prank(vaspOperator);
        wrapper = new PolicyWrapper(
            vaspOperator,            // initialOwner
            address(abt),            // sovToken (underlying ABT)
            1 days,                  // timeoutReject_
            "Wrapped TABT",          // name_
            "wTABT",                 // symbol_
            address(policyManager),  // policyManager_
            address(adminControls)   // adminControls_
        );

        // --- Authorize the wrapper to move underlying ABT (issuer/registrar does this) ---
        vm.prank(issuer);
        adminControls.authorizeWrapper(address(abt), address(wrapper), true);

        // --- Allow wrapper to run policies (compliance admin does this) ---
        vm.prank(complianceAdmin);
        policyManager.setRunner(address(wrapper), true);

        // --- Deploy and register policies (compliance admin deploys + registers) ---
        vm.startPrank(complianceAdmin);

        volumeThresholdPolicy = new VolumeThresholdPolicy(LOWER_THRESHOLD, UPPER_THRESHOLD);
        policyManager.addPolicy(address(volumeThresholdPolicy));

        // version = 1, require originator + beneficiary KYC, VASPs not required for now
        kycPolicy = new KYCPolicy(
            1,
            true,   // requireOriginatorCustomerKyc
            true,   // requireBeneficiaryCustomerKyc
            false   // requireVaspKyc
        );
        policyManager.addPolicy(address(kycPolicy));

        vm.stopPrank();

        // --- Mint TABT to Alice (issuer does this) ---
        vm.prank(issuer);
        abt.mint(alice, 10_000);
    }

    function testDeploymentAndWiring() public view {
        // ABT should point to AdminControls
        assertEq(address(abt.adminControls()), address(adminControls), "ABT adminControls not set");

        // Wrapper should point to AdminControls
        assertEq(address(wrapper.adminControls()), address(adminControls), "Wrapper adminControls not set");

        // Wrapper must be authorized for this ABT in AdminControls (multi-wrapper model)
        assertTrue(
            adminControls.isAuthorizedWrapper(address(abt), address(wrapper)),
            "Wrapper not authorized for ABT"
        );

        // PolicyManager owner should be complianceAdmin
        assertEq(policyManager.owner(), complianceAdmin, "PolicyManager owner mismatch");

        // Wrapper should be registered as a runner
        assertTrue(policyManager.isRunner(address(wrapper)), "Wrapper not runner");

        // Two policies should be registered
        address[] memory registeredPolicies = policyManager.getPolicies();
        assertEq(registeredPolicies.length, 2, "Unexpected policy count");
        assertEq(registeredPolicies[0], address(volumeThresholdPolicy), "VolumeThresholdPolicy not registered");
        assertEq(registeredPolicies[1], address(kycPolicy), "KYCPolicy not registered");
    }

    function testAssetTransferRestriction() public {
        uint256 amount = 1_000 * 10 ** abt.decimals();

        vm.startPrank(alice);
        // With Option A, ABT checks AdminControls allowlist + recovery authority.
        // Direct user transfer should revert:
        vm.expectRevert(bytes("ABT: transfers restricted"));
        abt.transfer(bob, amount);
        vm.stopPrank();
    }

    function testCompliantTransaction() public {
        // Identity provider sets KYC identities
        vm.startPrank(identityProvider);
        identityRegistry.setIdentity(
            alice,
            keccak256(abi.encodePacked("ALICE_ID")),
            keccak256(abi.encodePacked("ALICE_KYC"))
        );
        identityRegistry.setIdentity(
            bob,
            keccak256(abi.encodePacked("BOB_ID")),
            keccak256(abi.encodePacked("BOB_KYC"))
        );
        vm.stopPrank();

        // 1. Alice wraps 50 tokens
        vm.startPrank(alice);
        abt.approve(address(wrapper), 50);
        wrapper.depositFor(alice, 50);

        // 2. Alice transfers 50 wrapped TABT to Bob
        wrapper.transfer(bob, 50);
        vm.stopPrank();

        // 3. Bob should have 50 wrapped TABT
        uint256 bobWrappedBalance = wrapper.balanceOf(bob);
        assertEq(bobWrappedBalance, 50, "Bob did not receive 50 wrapped TABT from Alice.");
    }

    function testNonCompliantKYCTransaction() public {
        // Identity provider sets KYC — but give Alice INVALID (zero) kycHash.
        vm.startPrank(identityProvider);

        identityRegistry.setIdentity(
            alice,
            keccak256(abi.encodePacked("ALICE_ID")),
            bytes32(0) // INVALID KYC
        );

        identityRegistry.setIdentity(
            bob,
            keccak256(abi.encodePacked("BOB_ID")),
            keccak256(abi.encodePacked("BOB_KYC"))
        );
        vm.stopPrank();

        // 1. Alice wraps 50 tokens
        vm.startPrank(alice);
        abt.approve(address(wrapper), 50);
        wrapper.depositFor(alice, 50);

        // 2. Alice attempts transfer → should revert
        vm.expectRevert("PolicyProtected: policy check failed");
        wrapper.transfer(bob, 50);

        vm.stopPrank();

        // 3. Bob should still have 0
        assertEq(wrapper.balanceOf(bob), 0, "Bob should not receive tokens if Alice lacks KYC.");
    }

    function testNonCompliantCFMTransaction() public {
        // KYC ok
        vm.startPrank(identityProvider);
        identityRegistry.setIdentity(
            alice,
            keccak256(abi.encodePacked("ALICE_ID")),
            keccak256(abi.encodePacked("ALICE_KYC"))
        );
        identityRegistry.setIdentity(
            bob,
            keccak256(abi.encodePacked("BOB_ID")),
            keccak256(abi.encodePacked("BOB_KYC"))
        );
        vm.stopPrank();

        // Wrap 300
        vm.startPrank(alice);
        abt.approve(address(wrapper), 300);
        wrapper.depositFor(alice, 300);

        // Transfer 250 (>200) should fail
        vm.expectRevert();
        wrapper.transfer(bob, 250);
        vm.stopPrank();

        assertEq(wrapper.balanceOf(bob), 0, "Bob should not receive tokens if threshold policy fails.");
    }

    function testPendingCFMTransactionAndManualApproval() public {
        // KYC ok
        vm.startPrank(identityProvider);
        identityRegistry.setIdentity(
            alice,
            keccak256(abi.encodePacked("ALICE_ID")),
            keccak256(abi.encodePacked("ALICE_KYC"))
        );
        identityRegistry.setIdentity(
            bob,
            keccak256(abi.encodePacked("BOB_ID")),
            keccak256(abi.encodePacked("BOB_KYC"))
        );
        vm.stopPrank();

        // Wrap 300
        vm.startPrank(alice);
        abt.approve(address(wrapper), 300);
        wrapper.depositFor(alice, 300);

        // This assumes VolumeThresholdPolicy returns Pending for 150
        wrapper.transfer(bob, 150);
        vm.stopPrank();

        PolicyWrapper.TxData memory txData = wrapper.getTxData(0);
        assertEq(uint256(txData.status), uint256(PolicyWrapper.Status.Pending), "Tx should be Pending");
        assertEq(txData.from, alice, "Pending tx from mismatch");
        assertEq(txData.to, bob, "Pending tx to mismatch");
        assertEq(txData.amount, 150, "Pending tx amount mismatch");
        assertEq(wrapper.balanceOf(bob), 0, "Bob should not receive tokens while Pending");

        // Resolve pending policy (compliance admin)
        vm.prank(complianceAdmin);
        policyManager.resolvePending(address(volumeThresholdPolicy), true);

        // Execute pending tx (wrapper operator)
        vm.prank(vaspOperator);
        wrapper.executePendingTx(0);

        PolicyWrapper.TxData memory txAfter = wrapper.getTxData(0);
        assertEq(uint256(txAfter.status), uint256(PolicyWrapper.Status.Accepted), "Tx should be Accepted");
        assertGt(txAfter.timeout, block.timestamp, "Accepted tx should have future timeout");
        assertEq(wrapper.balanceOf(bob), 150, "Bob should receive tokens after execution");
    }

    function testTwoPendingTransactionsDoNotConflict() public {
        // KYC ok for all
        vm.startPrank(identityProvider);
        identityRegistry.setIdentity(
            alice,
            keccak256(abi.encodePacked("ALICE_ID")),
            keccak256(abi.encodePacked("ALICE_KYC"))
        );
        identityRegistry.setIdentity(
            bob,
            keccak256(abi.encodePacked("BOB_ID")),
            keccak256(abi.encodePacked("BOB_KYC"))
        );
        identityRegistry.setIdentity(
            charlie,
            keccak256(abi.encodePacked("CHARLIE_ID")),
            keccak256(abi.encodePacked("CHARLIE_KYC"))
        );
        vm.stopPrank();

        vm.startPrank(alice);
        abt.approve(address(wrapper), 500);
        wrapper.depositFor(alice, 500);

        // Open tx0
        wrapper.transfer(bob, 150);
        PolicyWrapper.TxData memory tx0 = wrapper.getTxData(0);
        assertEq(uint256(tx0.status), uint256(PolicyWrapper.Status.Pending), "tx0 should be Pending");
        assertEq(wrapper.balanceOf(bob), 0, "Bob should have 0 while Pending");

        // Open tx1
        wrapper.transfer(charlie, 150);
        PolicyWrapper.TxData memory tx1 = wrapper.getTxData(1);
        assertEq(uint256(tx1.status), uint256(PolicyWrapper.Status.Pending), "tx1 should be Pending");
        assertEq(wrapper.balanceOf(charlie), 0, "Charlie should have 0 while Pending");

        vm.stopPrank();

        uint256 aliceWrappedBefore = wrapper.balanceOf(alice);

        // Resolve + execute only tx0
        vm.prank(complianceAdmin);
        policyManager.resolvePending(address(volumeThresholdPolicy), true);

        vm.prank(vaspOperator);
        wrapper.executePendingTx(0);

        PolicyWrapper.TxData memory tx0After = wrapper.getTxData(0);
        assertEq(uint256(tx0After.status), uint256(PolicyWrapper.Status.Accepted), "tx0 should be Accepted");
        assertEq(wrapper.balanceOf(bob), 150, "Bob should receive 150 after tx0 execution");

        PolicyWrapper.TxData memory tx1After = wrapper.getTxData(1);
        assertEq(uint256(tx1After.status), uint256(PolicyWrapper.Status.Pending), "tx1 should remain Pending");
        assertEq(wrapper.balanceOf(charlie), 0, "Charlie should still have 0 while tx1 is Pending");

        uint256 aliceWrappedAfter = wrapper.balanceOf(alice);
        assertEq(aliceWrappedBefore - aliceWrappedAfter, 150, "Only executed tx0 should affect Alice");
    }
}
