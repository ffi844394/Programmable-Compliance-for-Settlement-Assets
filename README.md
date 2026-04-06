# Programmable Compliance
To-do

## Table of Contents
1. [Introduction](#introduction)
2. [Core Standards](#core-standards)
3. [Architecture Overview](#architecture-overview)
4. [Illustrative Actions](#illustrative-actions)

## Introduction
This repository provides a sample implementation of programmable compliance for settlement assets, demonstrating how regulated digital assets can be transferred under policy-enforced, auditable, and extensible compliance controls.

The implementation adopts a modular architecture that separates asset logic from compliance enforcement, enabling flexible and composable policy application across different token types and transaction contexts. Where relevant, the design is informed by concepts from the GL1 Programmable Compliance Toolkit Reference Model, but is adapted to reflect the specific requirements of settlement asset use cases. The key features implemented are:

- **Administrative Control** handles the underlying asset’s global administrative functions;
- **Policy Wrapper** routes all asset transfers through a policy-enforced execution corridor;
- **Policy Manager** orchestrates and aggregates compliance evaluations across registered rules;
- **Identity Management** supplies privacy-preserving party-level attestations for policy evaluation; and
- **Compliance Rules Engine** performs the necessary computations and checks, and produces automated (`Pass`/`Fail`) or deferred outcomes (`Pending`), enabling both straight-through processing and if required, manual review prior to execution.

For further details on how these key features are implemented in this POC, please refer to [Architecture Overview](#architecture-overview).

The design also intends to mirror real-world financial market structures, where issuers, custodians (VASPs), compliance functions, and identity providers operate as distinct roles, rather than a single monolithic authority.

This repository is intended as a **reference and educational example**, not a complete production system.

## Architecture Overview
These key components work together to embed regulatory compliance directly into digital asset transaction flows in an auditable, adaptable, and interoperable manner. 

| PC Toolkit Key Feature | Functions | Repo’s Implementation |
|---|---|---|
| Administrative Control | Enables regulatory intervention, risk management, and emergency response through explicit administrative oversight, distinct from user-initiated activity. | - Administrative authority is separated from regular user activity.<br>- A dedicated `AdminControls` contract governs which policy wrappers are authorised to custody and move the underlying asset.<br>- Administrative actions (e.g. authorising or revoking wrappers) are architecturally distinct from user-initiated transfers.<br> |
| Policy Wrapper | Decouples compliance logic from immutable asset contracts, enabling the same asset to operate under different regulatory or jurisdictional frameworks. | - The underlying asset token is deliberately restricted and not freely transferable.<br>- All user-initiated value movement occurs through a `PolicyWrapper`.<br> |  
| Policy Manager | Acts as the orchestration layer coordinating compliance evaluation across multiple specialised modules, providing a standardised interface to policy wrappers. | - Policy wrappers submit transaction contexts through a uniform interface.<br>- Individual compliance rules are implemented as modular policy contracts and registered with the `PolicyManager`.<br>- The `PolicyManager` aggregates policy outcomes and returns a single compliance attestation (`Pass`, `Fail`, or `Pending`).<br>- This avoids duplicated integrations across wrappers and ensures consistent application of compliance logic across all transactions.<br>- *Note*: The POC uses on-chain policy contracts for evaluation, while other implementations may support coordination with off-chain modules. |  
| Identity Management | Provides a unified view of entity identity to support KYC, AML, and CFT controls across fragmented blockchain address spaces while preserving privacy. | - Identity information is represented using hashed attestations, avoiding on-chain storage of personal data.<br>- Compliance policies query the registry to determine whether required identity conditions are satisfied.<br>- This enables entity-level compliance without exposing sensitive information on-chain.<br> - *Note*: Advanced mechanisms such as credential issuance, revocation registries, or cryptographic proofs are excluded in this POC but architecturally compatible. |  

Together, the key features form a layered compliance architecture consistent with the PC Toolkit Reference Model. Execution, orchestration, identity attestation, and rule evaluation are separated into distinct components, enabling flexibility, auditability, and controlled evolution of compliance logic over time.

This modular architecture allows policies, identity frameworks, and transfer corridors to evolve independently.

## Illustrative Actions

The following illustrates a transaction flow using the sample implementation in this repository:

1. **Wrapping the underlying asset**\
Alice holds units of the underlying AssetBackedToken (ABT).\
Alice instructs the `PolicyWrapper` to wrap a specified amount of ABT.\
The wrapper takes custody of the ABT and mints an equivalent amount of wrapped tokens to Alice.


2. **Initiating a wrapped token transfer**\
Alice initiates a transfer of wrapped tokens to Bob.\
The transfer is captured by the PolicyWrapper and is not executed immediately.


3. **Transaction Envelope construction**\
The PolicyWrapper submits the transfer intent to the PolicyManager.\
The PolicyManager constructs a transaction envelope containing the structured context required for compliance evaluation, including the originator, beneficiary, and transaction amount (with asset context implicit via the wrapper).


4. **Party packet enrichment**\
As part of policy evaluation, the IdentityRegistry is consulted to enrich the transaction envelope with party-level attestations (e.g. presence of valid KYC records for the originator and beneficiary).

5. **Policy evaluation**\
The PolicyManager submits the transaction envelope to all registered compliance policies.\
Each policy independently evaluates the transaction and returns an outcome.\
In the happy path, all policies return a `Pass` outcome.
> In some cases, one or more compliance policies may return a `Pending` outcome rather than an immediate pass or fail (i.e., transactions that fall within a conditional threshold requiring additional review).
> When this occurs:
>- The `PolicyManager` aggregates policy outcomes and returns a compliance attestation indicating `Pending`.
>- The PolicyWrapper does **not** execute the transfer.
>- Instead, the transaction envelope is materialised and stored on-chain as a pending transaction record.
>- No wrapped tokens are transferred while the transaction remains pending, ensuring that value does not move prior to compliance resolution.

6. **Compliance attestation and execution**\
The PolicyManager aggregates the policy outcomes and returns a compliance attestation indicating approval.\
Upon receipt of this attestation, the PolicyWrapper executes the transfer, debiting wrapped tokens from Alice and crediting wrapped tokens to Bob.

7. **Redemption (unwrapping)**\
Bob later initiates redemption of his wrapped tokens.\
The PolicyWrapper burns the wrapped tokens and releases the corresponding amount of ABT back to Bob.
