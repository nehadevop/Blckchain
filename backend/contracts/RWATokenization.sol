// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "../contracts/access/Ownable.sol";
import "../contracts/utils/Counters.sol";

/**
 * @title RWATokenization
 * @dev Contract for tokenizing Real World Assets as NFTs
 */
contract RWATokenization is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    // Mapping from token ID to asset value (in USD)
    mapping(uint256 => uint256) private _assetValues;
    
    // Mapping from token ID to asset status (true if verified)
    mapping(uint256 => bool) private _assetVerified;
    
    // Mapping from token ID to asset location
    mapping(uint256 => string) private _assetLocations;
    
    // Mapping to track if token is being used as collateral
    mapping(uint256 => bool) private _isCollateral;
    
    // Verifier addresses that can verify assets
    mapping(address => bool) private _verifiers;
    
    // Events
    event AssetTokenized(address indexed owner, uint256 indexed tokenId, uint256 value, string location, string metadataURI);
    event AssetVerified(uint256 indexed tokenId, address indexed verifier);
    event AssetValueUpdated(uint256 indexed tokenId, uint256 newValue);
    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);
    event CollateralStatusChanged(uint256 indexed tokenId, bool isCollateral);
    
    constructor() ERC721("Real World Asset Token", "RWAT") Ownable() {}
    
    /**
     * @dev Add a verifier who can verify tokenized assets
     * @param verifier Address of the verifier
     */
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "Invalid address");
        _verifiers[verifier] = true;
        emit VerifierAdded(verifier);
    }
    
    /**
     * @dev Remove a verifier
     * @param verifier Address of the verifier to remove
     */
    function removeVerifier(address verifier) external onlyOwner {
        require(_verifiers[verifier], "Not a verifier");
        _verifiers[verifier] = false;
        emit VerifierRemoved(verifier);
    }
    
    /**
     * @dev Tokenize a real world asset
     * @param recipient The owner of the tokenized asset
     * @param assetValue Value of the asset in USD (multiplied by 100 for 2 decimal precision)
     * @param location Physical location of the asset
     * @param metadataURI URI containing metadata about the asset (IPFS URI)
     * @return tokenId of the newly created token
     */
    function tokenizeAsset(
        address recipient,
        uint256 assetValue,
        string memory location,
        string memory metadataURI
    ) external returns (uint256) {
        require(recipient != address(0), "Invalid recipient");
        require(assetValue > 0, "Asset value must be positive");
        
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        _mint(recipient, newTokenId);
        _setTokenURI(newTokenId, metadataURI);
        
        _assetValues[newTokenId] = assetValue;
        _assetLocations[newTokenId] = location;
        _assetVerified[newTokenId] = false;
        _isCollateral[newTokenId] = false;
        
        emit AssetTokenized(recipient, newTokenId, assetValue, location, metadataURI);
        
        return newTokenId;
    }
    
    /**
     * @dev Verify a tokenized asset
     * @param tokenId ID of the token to verify
     */
    function verifyAsset(uint256 tokenId) external {
        require(_verifiers[msg.sender], "Not authorized to verify");
        require(_exists(tokenId), "Token does not exist");
        require(!_assetVerified[tokenId], "Asset already verified");
        
        _assetVerified[tokenId] = true;
        
        emit AssetVerified(tokenId, msg.sender);
    }
    
    /**
     * @dev Update the value of a tokenized asset
     * @param tokenId ID of the token to update
     * @param newValue New value of the asset in USD
     */
    function updateAssetValue(uint256 tokenId, uint256 newValue) external {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender || _verifiers[msg.sender], "Not authorized");
        require(newValue > 0, "Asset value must be positive");
        require(!_isCollateral[tokenId], "Asset is being used as collateral");
        
        _assetValues[tokenId] = newValue;
        
        emit AssetValueUpdated(tokenId, newValue);
    }
    
    /**
     * @dev Set collateral status (called by Loan Contract)
     * @param tokenId ID of the token
     * @param collateralStatus Whether the asset is being used as collateral
     */
    function setCollateralStatus(uint256 tokenId, bool collateralStatus) external {
        require(_exists(tokenId), "Token does not exist");
        // In production, add access control to ensure only loan contracts can call this
        
        _isCollateral[tokenId] = collateralStatus;
        
        emit CollateralStatusChanged(tokenId, collateralStatus);
    }
    
    // Getter functions
    
    function getAssetValue(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");
        return _assetValues[tokenId];
    }
    
    function isAssetVerified(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Token does not exist");
        return _assetVerified[tokenId];
    }
    
    function getAssetLocation(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return _assetLocations[tokenId];
    }
    
    function isCollateral(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Token does not exist");
        return _isCollateral[tokenId];
    }
    
    function isVerifier(address account) external view returns (bool) {
        return _verifiers[account];
    }
    
    /**
     * @dev Override _beforeTokenTransfer to prevent transfer of collateralized assets
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        require(!_isCollateral[tokenId], "Asset is being used as collateral");
        return super._update(to, tokenId, auth);
    }
}
