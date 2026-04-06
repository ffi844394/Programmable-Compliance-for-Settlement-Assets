# Programmable Compliance – Solidity Implementation

This folder contains the **Solidity reference implementation** of a programmable compliance architecture for asset-backed tokens, built using the **Foundry (Forge)** framework.

The contracts demonstrate how compliance logic (KYC, volume thresholds, manual approvals, administrative controls, etc.) can be enforced **before and during settlement**, using modular policy evaluation and wrapper-based transfer control.

---

## 1. Framework Overview: Foundry (Forge)

This repository uses **Foundry**, a fast and developer-friendly Ethereum development toolkit.

Key components used:

* **Forge** – compilation, testing, and scripting
* **Anvil** – local Ethereum devnet
* **forge-std** – testing utilities (`Test`, `vm`, `console`)

Official documentation:
[https://book.getfoundry.sh/](https://book.getfoundry.sh/)

---

## 2. Repository Structure

```
solidity/
├── src/                     # Core smart contracts
│   ├── AdministrativeControls/
│   ├── AssetBackedToken.sol
│   ├── PolicyWrapper/
│   ├── PolicyManager/
│   ├── IdentityManager/
│   ├── Policies/
│
├── test/                    # Unit and integration tests
│   ├── TransactionTest.t.sol
│   ├── AdminControlsTest.t.sol
│   └── ...
│
├── script/                  # Deployment scripts (Forge style)
│   ├── DeployAdminControls.s.sol
│   ├── DeployIdentityRegistry.s.sol
│   ├── DeployPolicyManager.s.sol
│   ├── DeployPolicies.s.sol
│   ├── DeploySettlementAssetToken.s.sol
│   ├── DeployPolicyWrapper.s.sol
│
└── README.md                # This file
```

### Folder intent

* **`src/`** – production contracts
* **`test/`** – executable specifications (unit + integration tests)
* **`script/`** – deterministic, reproducible deployment scripts

---

## 3. Running Tests

All tests are written using `forge-std` and can be executed locally.

### Run all tests

```bash
forge test
```

### Run with verbose output

```bash
forge test -vv
```

### Run a specific test file

```bash
forge test --match-path test/TransactionTest.t.sol
```

Tests cover:

* Policy enforcement (KYC, volume thresholds)
* Pending transactions and manual approvals
* Multi-wrapper / multi-policy-manager setups
* Administrative controls (pause, allowlists, recovery authority)

---

## 4. Environment Variables

Deployment scripts rely on **environment variables** to configure **roles and addresses**, while **transaction signing** is handled via `--private-key`.

**Design rule:**

* `--private-key` → who sends transactions
* `vm.env*()` → who becomes owner / operator / admin in contracts

### Common environment variables

```bash
export ISSUER=0x...
export COMPLIANCE_ADMIN=0x...
export IDENTITY_PROVIDER=0x...
export GOVERNOR=0x...
export REGISTRAR=0x...
export RECOVERY_OPS=0x...

# Optional policy parameters
export LOWER_THRESHOLD=100
export UPPER_THRESHOLD=200
```

It is recommended to store these in a `.env` file.

---

## 5. Deployment Model

Each contract is deployed via a **dedicated Forge script**, enabling:

* clear separation of responsibilities
* reuse across environments
* partial redeployments without resetting the system

### Transaction signing

All scripts use:

```solidity
vm.startBroadcast();
```

You must provide the private key at runtime:

```bash
--private-key <hex-private-key>
```

---

## 6. Deployment Order (From Scratch)

Deployment order matters because several contracts depend on previously deployed addresses.

### Required deployment sequence

1. **DeployAdminControls**
2. **DeployIdentityRegistry**
3. **DeployPolicyManager**
4. **DeployPolicies**
5. **DeploySettlementAssetToken**
6. **DeployPolicyWrapper**

---

### 6.1 Deploy AdminControls

```bash
forge script script/DeployAdminControls.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

Provides:

* global pause
* wrapper allowlists (multi-wrapper support)
* recovery authority gating

---

### 6.2 Deploy IdentityRegistry

```bash
forge script script/DeployIdentityRegistry.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

The IdentityRegistry is operated by an **identity provider** and stores:

* identity references
* KYC hashes (or other attestations)

---

### 6.3 Deploy PolicyManager

```bash
forge script script/DeployPolicyManager.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

The PolicyManager:

* orchestrates policy evaluation
* aggregates policy results
* supports **Pending → Manual Override → Execution**

---

### 6.4 Deploy Policies

```bash
forge script script/DeployPolicies.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

Typical policies include:

* `KYCPolicy`
* `VolumeThresholdPolicy`

#### Attaching policies to the PolicyManager

```solidity
policyManager.addPolicy(address(kycPolicy));
policyManager.addPolicy(address(volumeThresholdPolicy));
```

Only the **PolicyManager owner (compliance admin)** may add or remove policies.

---

### 6.5 Deploy Settlement Asset Token (ABT)

```bash
forge script script/DeploySettlementAssetToken.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

The AssetBackedToken:

* represents the settlement liability
* disallows direct user transfers
* can only be moved by authorized PolicyWrappers

---

### 6.6 Deploy PolicyWrapper

```bash
forge script script/DeployPolicyWrapper.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <DEPLOYER_KEY> \
  --broadcast
```

The PolicyWrapper:

* mediates all end-user transfers
* invokes PolicyManager prior to settlement
* supports Pending / Accepted / Rejected flows

Post-deployment requirements:

* authorize the wrapper in `AdminControls`
* register the wrapper as a runner in `PolicyManager`

---

## 7. Multi-Wrapper & Multi-Policy Support

The architecture explicitly supports:

* multiple PolicyWrappers per AssetBackedToken
* different PolicyManagers per wrapper
* different compliance rules per settlement rail

This enables:

* multiple VASPs settling the same asset
* jurisdiction-specific compliance regimes
* parallel policy evaluation paths

---

## 8. Local Development (Anvil)

Start a local devnet:

```bash
anvil
```

Default RPC:

```
http://127.0.0.1:8545
```

Anvil provides pre-funded test accounts and private keys.

---

## 9. Notes & Best Practices

* **Do not embed PII on-chain**
  - Identity resolution is abstracted via registries and hashes.

* **Policies should remain small and auditable**
  - Complex logic should be off-chain or oracle-assisted.

* **Administrative controls are centralized by design**
  - In production, roles should be multisigs or timelocks.

* **Tests are the canonical specification**
  - When in doubt, consult the tests.

---

## 10. Further Extensions

This reference implementation is designed to be extended with additional types of compliance checks such as:

* oracle-based sanctions checks
* ZK / MPC-based compliance attestations


