// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title RiskAssessmentOracle
 * @dev Oracle contract that manages risk scores for borrowers and assets
 */
contract RiskAssessmentOracle is AccessControl {
    using Counters for Counters.Counter;
    
    // Define roles
    bytes32 public constant RISK_ASSESSOR_ROLE = keccak256("RISK_ASSESSOR_ROLE");
    
    // Risk score ranges from 0 (highest risk) to 100 (lowest risk)
    
    // Mapping from borrower address to their risk score
    mapping(address => uint8) private _borrowerRiskScores;
    
    // Mapping from asset token ID to its risk score
    mapping(uint256 => uint8) private _assetRiskScores;
    
    // Mapping from borrower to their assessment timestamp
    mapping(address => uint256) private _borrowerAssessmentTimestamps;
    
    // Mapping from asset to its assessment timestamp
    mapping(uint256 => uint256) private _assetAssessmentTimestamps;
    
    // Assessment validity period (default: 90 days)
    uint256 private _assessmentValidityPeriod = 90 days;
    
    // Events
    event BorrowerRiskUpdated(address indexed borrower, uint8 riskScore);
    event AssetRiskUpdated(uint256 indexed assetId, uint8 riskScore);
    event AssessmentValidityPeriodUpdated(uint256 newPeriod);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_ASSESSOR_ROLE, msg.sender);
    }
    
    /**
     * @dev Set risk score for a borrower
     * @param borrower Address of the borrower
     * @param riskScore Risk score (0-100)
     */
    function setBorrowerRiskScore(address borrower, uint8 riskScore) external onlyRole(RISK_ASSESSOR_ROLE) {
        require(riskScore <= 100, "Risk score must be between 0 and 100");
        
        _borrowerRiskScores[borrower] = riskScore;
        _borrowerAssessmentTimestamps[borrower] = block.timestamp;
        
        emit BorrowerRiskUpdated(borrower, riskScore);
    }
    
    /**
     * @dev Set risk score for an asset
     * @param assetId Token ID of the asset
     * @param riskScore Risk score (0-100)
     */
    function setAssetRiskScore(uint256 assetId, uint8 riskScore) external onlyRole(RISK_ASSESSOR_ROLE) {
        require(riskScore <= 100, "Risk score must be between 0 and 100");
        
        _assetRiskScores[assetId] = riskScore;
        _assetAssessmentTimestamps[assetId] = block.timestamp;
        
        emit AssetRiskUpdated(assetId, riskScore);
    }
    
    /**
     * @dev Update the assessment validity period
     * @param newPeriod New validity period in seconds
     */
    function updateAssessmentValidityPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newPeriod > 0, "Validity period must be positive");
        _assessmentValidityPeriod = newPeriod;
        
        emit AssessmentValidityPeriodUpdated(newPeriod);
    }
    
    /**
     * @dev Get a borrower's risk score
     * @param borrower Address of the borrower
     * @return riskScore The borrower's risk score
     * @return valid Whether the assessment is still valid
     */
    function getBorrowerRiskScore(address borrower) external view returns (uint8 riskScore, bool valid) {
        riskScore = _borrowerRiskScores[borrower];
        valid = (block.timestamp - _borrowerAssessmentTimestamps[borrower]) <= _assessmentValidityPeriod;
    }
    
    /**
     * @dev Get an asset's risk score
     * @param assetId Token ID of the asset
     * @return riskScore The asset's risk score
     * @return valid Whether the assessment is still valid
     */
    function getAssetRiskScore(uint256 assetId) external view returns (uint8 riskScore, bool valid) {
        riskScore = _assetRiskScores[assetId];
        valid = (block.timestamp - _assetAssessmentTimestamps[assetId]) <= _assessmentValidityPeriod;
    }
    
    /**
     * @dev Get combined loan risk score (borrower + asset)
     * @param borrower Address of the borrower
     * @param assetId Token ID of the asset
     * @return combinedRiskScore The combined risk score
     * @return valid Whether both assessments are valid
     */
    function getCombinedRiskScore(address borrower, uint256 assetId) external view returns (uint8 combinedRiskScore, bool valid) {
        bool borrowerValid = (block.timestamp - _borrowerAssessmentTimestamps[borrower]) <= _assessmentValidityPeriod;
        bool assetValid = (block.timestamp - _assetAssessmentTimestamps[assetId]) <= _assessmentValidityPeriod;
        
        valid = borrowerValid && assetValid;
        
        if (valid) {
            // Weighted average: 60% borrower score, 40% asset score
            combinedRiskScore = uint8(
                (uint256(_borrowerRiskScores[borrower]) * 60 + uint256(_assetRiskScores[assetId]) * 40) / 100
            );
        } else {
            combinedRiskScore = 0;
        }
    }
    
    /**
     * @dev Get maximum recommended loan-to-value ratio based on risk score
     * @param riskScore Risk score (0-100)
     * @return maxLTV Maximum recommended LTV percentage
     */
    function getRecommendedMaxLTV(uint8 riskScore) external pure returns (uint8 maxLTV) {
        if (riskScore >= 90) {
            return 80; // 80% LTV for very low risk
        } else if (riskScore >= 75) {
            return 70; // 70% LTV for low risk
        } else if (riskScore >= 60) {
            return 60; // 60% LTV for medium risk
        } else if (riskScore >= 40) {
            return 50; // 50% LTV for medium-high risk
        } else if (riskScore >= 25) {
            return 40; // 40% LTV for high risk
        } else {
            return 30; // 30% LTV for very high risk
        }
    }
    
    /**
     * @dev Get assessment validity period
     * @return The current assessment validity period in seconds
     */
    function getAssessmentValidityPeriod() external view returns (uint256) {
        return _assessmentValidityPeriod;
    }
}