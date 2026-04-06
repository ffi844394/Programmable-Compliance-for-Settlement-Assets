// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./AdministrativeControls/IAdminControls.sol";

contract AssetBackedToken is ERC20, Ownable {
    // -------------------------
    // AdminControls (ecosystem-wide controls)
    // -------------------------
    IAdminControls public adminControls;

    // -------------------------
    // Metadata
    // -------------------------
    string private _supplementalInformationUri;

    // -------------------------
    // Events
    // -------------------------
    event AdminControlsUpdated(address indexed sender, address indexed oldAdmin, address indexed newAdmin);
    event SupplementalInformationUriUpdated(address indexed sender, string oldUri, string newUri);

    event CurrencyMinted(address indexed sender, address indexed recipient, uint256 amount);
    event CurrencyBurned(address indexed sender, address indexed source, uint256 amount);

    event CurrencyRecovered(address indexed sender, address indexed from, address indexed to, uint256 amount);

    // -------------------------
    // Modifiers
    // -------------------------
    modifier whenSystemNotPaused() {
        require(address(adminControls) != address(0), "ABT: adminControls not set");
        require(!adminControls.isSystemPaused(), "ABT: paused");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory supplementalInformationUriValue,
        address initialOwner,
        address adminControls_
    )
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {
        require(bytes(name_).length != 0, "ABT: name is empty");
        require(bytes(symbol_).length != 0, "ABT: symbol is empty");
        require(initialOwner != address(0), "ABT: owner is zero");
        require(adminControls_ != address(0), "ABT: adminControls is zero");

        adminControls = IAdminControls(adminControls_);
        _supplementalInformationUri = supplementalInformationUriValue;

        emit AdminControlsUpdated(msg.sender, address(0), adminControls_);
    }

    /// @notice 6 decimals (fiat-like units).
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function supplementalInformationUri() external view returns (string memory) {
        return _supplementalInformationUri;
    }

    function supplementalInformationUriUpdate(string memory newUri) external onlyOwner {
        emit SupplementalInformationUriUpdated(msg.sender, _supplementalInformationUri, newUri);
        _supplementalInformationUri = newUri;
    }

    // -------------------------
    // AdminControls pointer rotation (issuer-controlled)
    // -------------------------
    function setAdminControls(address newAdminControls) external onlyOwner {
        require(newAdminControls != address(0), "ABT: adminControls is zero");
        emit AdminControlsUpdated(msg.sender, address(adminControls), newAdminControls);
        adminControls = IAdminControls(newAdminControls);
    }

    // -------------------------
    // Mint / burn (issuer-controlled)
    // -------------------------
    function mint(address to, uint256 amount) external onlyOwner whenSystemNotPaused {
        require(to != address(0), "ABT: to is zero");
        require(amount != 0, "ABT: mint amount is zero");
        _mint(to, amount);
        emit CurrencyMinted(msg.sender, to, amount);
    }

    function burn(uint256 amount) external onlyOwner whenSystemNotPaused {
        require(amount != 0, "ABT: burn amount is zero");
        _burn(msg.sender, amount);
        emit CurrencyBurned(msg.sender, msg.sender, amount);
    }

    // -------------------------
    // Asset recovery (forced transfer / clawback)
    // -------------------------
    /// @notice Force-move tokens from `from` to `to` under recovery authority.
    /// @dev This bypasses wrapper-only restriction but still records a normal ERC20 transfer.
    ///      If you want recovery to be allowed even when paused, remove `whenSystemNotPaused`.
    function recover(address from, address to, uint256 amount) external whenSystemNotPaused {
        require(adminControls.canRecover(msg.sender), "ABT: not recovery admin");
        require(from != address(0), "ABT: from is zero");
        require(to != address(0), "ABT: to is zero");
        require(amount != 0, "ABT: amount is zero");

        _transfer(from, to, amount);
        emit CurrencyRecovered(msg.sender, from, to, amount);
    }

    // -------------------------
    // Transfer constraints (OZ v5: override _update)
    // -------------------------
    function _update(address from, address to, uint256 value) internal virtual override {
        require(address(adminControls) != address(0), "ABT: adminControls not set");
        require(!adminControls.isSystemPaused(), "ABT: paused");
        require(value != 0, "ABT: amount is zero");

        // Normal transfers (neither mint nor burn) must come from an authorized wrapper,
        // OR from a recovery admin (to allow recover()).
        if (from != address(0) && to != address(0)) {
            bool ok =
                adminControls.isAuthorizedWrapper(address(this), msg.sender) ||
                adminControls.canRecover(msg.sender);

            require(ok, "ABT: transfers restricted");
        }

        super._update(from, to, value);
    }
}
