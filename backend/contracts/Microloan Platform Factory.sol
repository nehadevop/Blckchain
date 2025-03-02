// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./RWATokenization.sol";
import "./LoanMarketplace.sol";
import "./RiskAssessmentOracle.sol";

/**
 * @title MicroloanPlatformFactory
 * @dev Factory contract to deploy and manage the RWA microloan platform
 */
contract MicroloanPlatformFactory is Ownable {
    // Deployed contract addresses
    RWATokenization public rwaTokenization;
    LoanMarketplace public loanMarketplace;
    RiskAssessmentOracle public riskAssessmentOracle;
    
    // Events
    event PlatformDeployed(
        address rwaTokenizationAddress,
        address loanMarketplaceAddress,
        address riskAssessmentOracleAddress
    );
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Deploy the complete RWA microloan platform
     */
    function deployPlatform() external onlyOwner {
        // Deploy RWA Tokenization contract
        rwaTokenization = new RWATokenization();
        
        // Deploy Risk Assessment Oracle
        riskAssessmentOracle = new RiskAssessmentOracle();
        
        // Deploy Loan Marketplace contract
        loanMarketplace = new LoanMarketplace(address(rwaTokenization));
        
        // Set up permissions for contracts to interact
        // Allow loan marketplace to modify collateral status
        rwaTokenization.addVerifier(owner());
        
        emit PlatformDeployed(
            address(rwaTokenization),
            address(loanMarketplace),
            address(riskAssessmentOracle)
        );
    }
    
    /**
     * @dev Get platform contract addresses
     * @return Platform contract addresses
     */
    function getPlatformContracts() external view returns (
        address rwaTokenizationAddr,
        address loanMarketplaceAddr,
        address riskAssessmentOracleAddr
    ) {
        return (
            address(rwaTokenization),
            address(loanMarketplace),
            address(riskAssessmentOracle)
        );
    }
}