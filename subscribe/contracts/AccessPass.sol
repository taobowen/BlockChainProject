// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AccessPass (OZ v5 compatible)
 */
contract AccessPass is ERC721, Ownable {
    uint256 public nextId;
    mapping(uint256 => uint256) public expiresAt; // tokenId -> expiry
    address public manager;
    string private _baseTokenURI;

    error NotManager();
    error InvalidManager();
    error InvalidToken();

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    // NOTE: Ownable in OZ v5 requires an initial owner in its constructor
    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner
    )
        ERC721(name_, symbol_)
        Ownable(initialOwner) // <-- pass argument to base constructor
    {}

    function setManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert InvalidManager();
        manager = newManager;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function mintTo(address to, uint256 expiry) external onlyManager returns (uint256 tokenId) {
        tokenId = ++nextId;
        _safeMint(to, tokenId);
        expiresAt[tokenId] = expiry;
    }

    /// @notice Manager can update expiry on renew/cancel flows.
    function setExpiry(uint256 tokenId, uint256 newExpiry) external onlyManager {
        // OZ v5: use _ownerOf(tokenId) rather than _exists()
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();
        expiresAt[tokenId] = newExpiry;
    }

    /// @notice Convenience view for UI/gating.
    function getExpiry(uint256 tokenId) external view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) revert InvalidToken();
        return expiresAt[tokenId];
    }
}
