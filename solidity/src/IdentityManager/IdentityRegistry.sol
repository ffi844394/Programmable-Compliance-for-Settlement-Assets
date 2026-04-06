// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPolicy.sol";

/// @notice Minimal identity registry for PoC.
///         Maps wallet -> (identityRef, kycHash).
contract IdentityRegistry {
    struct IdentityRecord {
        bytes32 identityRef;
        bytes32 kycHash;
    }

    address public owner;

    mapping(address => IdentityRecord) private _records;

    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event IdentityUpdated(
        address indexed wallet,
        bytes32 identityRef,
        bytes32 kycHash
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "IdentityRegistry: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "IdentityRegistry: owner is zero");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Set or update identity metadata for a wallet.
    function setIdentity(
        address wallet,
        bytes32 identityRef,
        bytes32 kycHash
    ) external onlyOwner {
        require(wallet != address(0), "IdentityRegistry: wallet is zero");

        _records[wallet] = IdentityRecord({
            identityRef: identityRef,
            kycHash: kycHash
        });

        emit IdentityUpdated(wallet, identityRef, kycHash);
    }

    /// @notice Return the raw record (identityRef, kycHash).
    function getIdentity(
        address wallet
    ) external view returns (bytes32 identityRef, bytes32 kycHash) {
        IdentityRecord memory rec = _records[wallet];
        return (rec.identityRef, rec.kycHash);
    }

    /// @notice Helper: return a PartyPacket compatible with IPolicy.
    function getPartyPacket(
        address wallet
    ) external view returns (IPolicy.PartyPacket memory packet) {
        IdentityRecord memory rec = _records[wallet];
        packet = IPolicy.PartyPacket({
            role: IPolicy.PartyRole.Unknown,
            wallet: wallet,
            identityRef: rec.identityRef,
            kycHash: rec.kycHash,
            accountRef: bytes32(0),
            jurisdiction: bytes32(0)
        });
    }
}
