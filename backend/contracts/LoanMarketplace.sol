// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../contracts/token/ERC20/IERC20.sol";
import "../contracts/access/Ownable.sol";
import "../contracts/security/ReentrancyGuard.sol";
import "./RWATokenization.sol";

/**
 * @title LoanMarketplace
 * @dev Contract for managing loan offers and requests using RWA as collateral
 */
contract LoanMarketplace is Ownable, ReentrancyGuard {
    // RWA Tokenization contract
    RWATokenization private _rwaToken;
    
    // Loan statuses
    enum LoanStatus { OFFERED, ACTIVE, REPAID, DEFAULTED, CANCELED }
    
    // Loan offer structure
    struct LoanOffer {
        uint256 loanAmount;           // Amount in stablecoin (e.g., USDC)
        uint256 interestRate;         // Annual interest rate (multiplied by 100 for precision)
        uint256 durationDays;         // Loan duration in days
        address lender;               // Address of the lender
        address stablecoin;           // Address of the stablecoin used for the loan
        LoanStatus status;            // Current status of the loan
        uint256 collateralTokenId;    // RWA token ID used as collateral
        address borrower;             // Address of the borrower (initially zero)
        uint256 startTime;            // Timestamp when loan became active
        uint256 endTime;              // Timestamp when loan is due
        uint256 remainingAmount;      // Remaining amount to be repaid
    }
    
    // Counter for loan offers
    uint256 private _loanOfferId = 0;
    
    // Mapping from offer ID to loan offer details
    mapping(uint256 => LoanOffer) private _loanOffers;
    
    // Platform fee percentage (multiplied by 100 for precision)
    uint256 private _platformFeePercent = 100; // 1% default
    
    // Risk assessment contract (if implementing)
    address private _riskAssessor;
    
    // Events
    event LoanOfferCreated(uint256 indexed offerId, address indexed lender, uint256 amount, uint256 interestRate, uint256 durationDays, uint256 collateralTokenId);
    event LoanOfferAccepted(uint256 indexed offerId, address indexed borrower, uint256 amount);
    event LoanRepayment(uint256 indexed offerId, address indexed borrower, uint256 amount);
    event LoanFullyRepaid(uint256 indexed offerId, address indexed borrower);
    event LoanDefaulted(uint256 indexed offerId, address indexed borrower);
    event LoanOfferCanceled(uint256 indexed offerId, address indexed lender);
    event PlatformFeeUpdated(uint256 newFeePercent);
    event CollateralClaimed(uint256 indexed offerId, address indexed lender, uint256 tokenId);
    
    constructor(address rwaTokenAddress) Ownable(msg.sender) {
        _rwaToken = RWATokenization(rwaTokenAddress);
    }
    
    /**
     * @dev Update the platform fee percentage
     * @param newFeePercent New fee percentage (multiplied by 100 for precision)
     */
    function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
        _platformFeePercent = newFeePercent;
        emit PlatformFeeUpdated(newFeePercent);
    }
    
    /**
     * @dev Create a loan offer using RWA as collateral
     * @param amount Loan amount in stablecoin
     * @param interestRate Annual interest rate (multiplied by 100 for precision)
     * @param durationDays Loan duration in days
     * @param collateralTokenId RWA token ID used as collateral
     * @param stablecoin Address of the stablecoin contract
     */
    function createLoanOffer(
        uint256 amount,
        uint256 interestRate,
        uint256 durationDays,
        uint256 collateralTokenId,
        address stablecoin
    ) external returns (uint256) {
        require(amount > 0, "Loan amount must be positive");
        require(interestRate > 0, "Interest rate must be positive");
        require(durationDays > 0, "Duration must be positive");
        require(stablecoin != address(0), "Invalid stablecoin address");
        
        // Check if the collateral token exists and is verified
        require(_rwaToken.ownerOf(collateralTokenId) == msg.sender, "Not the owner of the token");
        require(_rwaToken.isAssetVerified(collateralTokenId), "Asset not verified");
        require(!_rwaToken.isCollateral(collateralTokenId), "Asset already used as collateral");
        
        // Get the asset value and ensure loan amount is appropriate
        uint256 assetValue = _rwaToken.getAssetValue(collateralTokenId);
        require(amount <= assetValue * 70 / 100, "Loan amount exceeds 70% of asset value");
        
        // Create a new loan offer
        uint256 offerId = _loanOfferId++;
        
        _loanOffers[offerId] = LoanOffer({
            loanAmount: amount,
            interestRate: interestRate,
            durationDays: durationDays,
            lender: msg.sender,
            stablecoin: stablecoin,
            status: LoanStatus.OFFERED,
            collateralTokenId: collateralTokenId,
            borrower: address(0),
            startTime: 0,
            endTime: 0,
            remainingAmount: 0
        });
        
        // Set the asset as collateral
        _rwaToken.setCollateralStatus(collateralTokenId, true);
        
        emit LoanOfferCreated(offerId, msg.sender, amount, interestRate, durationDays, collateralTokenId);
        
        return offerId;
    }
    
    /**
     * @dev Accept a loan offer
     * @param offerId ID of the loan offer to accept
     */
    function acceptLoanOffer(uint256 offerId) external nonReentrant {
        LoanOffer storage offer = _loanOffers[offerId];
        
        require(offer.status == LoanStatus.OFFERED, "Offer not available");
        require(offer.borrower == address(0), "Offer already taken");
        require(_rwaToken.ownerOf(offer.collateralTokenId) == msg.sender, "Not the owner of collateral");
        
        IERC20 stablecoin = IERC20(offer.stablecoin);
        
        // Check if lender has enough balance and approved the contract
        require(stablecoin.balanceOf(offer.lender) >= offer.loanAmount, "Lender has insufficient balance");
        require(stablecoin.allowance(offer.lender, address(this)) >= offer.loanAmount, "Lender has not approved transfer");
        
        // Calculate platform fee
        uint256 platformFee = (offer.loanAmount * _platformFeePercent) / 10000;
        uint256 amountAfterFee = offer.loanAmount - platformFee;
        
        // Transfer stablecoin from lender to borrower
        require(stablecoin.transferFrom(offer.lender, msg.sender, amountAfterFee), "Stablecoin transfer failed");
        
        // Transfer platform fee
        if (platformFee > 0) {
            require(stablecoin.transferFrom(offer.lender, owner(), platformFee), "Fee transfer failed");
        }
        
        // Update loan details
        offer.borrower = msg.sender;
        offer.status = LoanStatus.ACTIVE;
        offer.startTime = block.timestamp;
        offer.endTime = block.timestamp + (offer.durationDays * 1 days);
        
        // Calculate full repayment amount with interest
        uint256 interest = (offer.loanAmount * offer.interestRate * offer.durationDays) / (36500); // Daily interest
        offer.remainingAmount = offer.loanAmount + interest;
        
        emit LoanOfferAccepted(offerId, msg.sender, amountAfterFee);
    }
    
    /**
     * @dev Make a loan repayment
     * @param offerId ID of the loan to repay
     * @param amount Amount to repay
     */
    function repayLoan(uint256 offerId, uint256 amount) external nonReentrant {
        LoanOffer storage offer = _loanOffers[offerId];
        
        require(offer.status == LoanStatus.ACTIVE, "Loan not active");
        require(offer.borrower == msg.sender, "Not the borrower");
        require(amount > 0, "Amount must be positive");
        require(amount <= offer.remainingAmount, "Amount exceeds remaining debt");
        
        IERC20 stablecoin = IERC20(offer.stablecoin);
        
        // Check if borrower has approved the transfer
        require(stablecoin.allowance(msg.sender, address(this)) >= amount, "Repayment not approved");
        
        // Transfer repayment from borrower to lender
        require(stablecoin.transferFrom(msg.sender, offer.lender, amount), "Repayment transfer failed");
        
        // Update remaining amount
        offer.remainingAmount -= amount;
        
        emit LoanRepayment(offerId, msg.sender, amount);
        
        // Check if fully repaid
        if (offer.remainingAmount == 0) {
            offer.status = LoanStatus.REPAID;
            
            // Release collateral
            _rwaToken.setCollateralStatus(offer.collateralTokenId, false);
            
            emit LoanFullyRepaid(offerId, msg.sender);
        }
    }
    
    /**
     * @dev Declare a loan as defaulted (can only be called after loan end time)
     * @param offerId ID of the defaulted loan
     */
    function declareLoanDefault(uint256 offerId) external nonReentrant {
        LoanOffer storage offer = _loanOffers[offerId];
        
        require(offer.status == LoanStatus.ACTIVE, "Loan not active");
        require(offer.lender == msg.sender, "Not the lender");
        require(block.timestamp > offer.endTime, "Loan not yet due");
        require(offer.remainingAmount > 0, "Loan already repaid");
        
        // Mark as defaulted
        offer.status = LoanStatus.DEFAULTED;
        
        emit LoanDefaulted(offerId, offer.borrower);
    }
    
    /**
     * @dev Claim collateral for a defaulted loan
     * @param offerId ID of the defaulted loan
     */
    function claimCollateral(uint256 offerId) external nonReentrant {
        LoanOffer storage offer = _loanOffers[offerId];
        
        require(offer.status == LoanStatus.DEFAULTED, "Loan not defaulted");
        require(offer.lender == msg.sender, "Not the lender");
        
        // Transfer the collateral to the lender
        _rwaToken.transferFrom(offer.borrower, msg.sender, offer.collateralTokenId);
        
        // Keep collateral status as true since it's still collateral
        
        emit CollateralClaimed(offerId, msg.sender, offer.collateralTokenId);
    }
    
    /**
     * @dev Cancel a loan offer that hasn't been accepted
     * @param offerId ID of the loan offer to cancel
     */
    function cancelLoanOffer(uint256 offerId) external nonReentrant {
        LoanOffer storage offer = _loanOffers[offerId];
        
        require(offer.status == LoanStatus.OFFERED, "Cannot cancel active loan");
        require(offer.lender == msg.sender, "Not the lender");
        require(offer.borrower == address(0), "Loan already accepted");
        
        // Mark as canceled
        offer.status = LoanStatus.CANCELED;
        
        // Release collateral status
        _rwaToken.setCollateralStatus(offer.collateralTokenId, false);
        
        emit LoanOfferCanceled(offerId, msg.sender);
    }
    
    // Getter functions
    
    function getLoanOffer(uint256 offerId) external view returns (
        uint256 loanAmount,
        uint256 interestRate,
        uint256 durationDays,
        address lender,
        address stablecoin,
        LoanStatus status,
        uint256 collateralTokenId,
        address borrower,
        uint256 startTime,
        uint256 endTime,
        uint256 remainingAmount
    ) {
        LoanOffer storage offer = _loanOffers[offerId];
        
        return (
            offer.loanAmount,
            offer.interestRate,
            offer.durationDays,
            offer.lender,
            offer.stablecoin,
            offer.status,
            offer.collateralTokenId,
            offer.borrower,
            offer.startTime,
            offer.endTime,
            offer.remainingAmount
        );
    }
    
    function getLoanStatus(uint256 offerId) external view returns (LoanStatus) {
        return _loanOffers[offerId].status;
    }
    
    function getPlatformFee() external view returns (uint256) {
        return _platformFeePercent;
    }
    
    function getLoanCount() external view returns (uint256) {
        return _loanOfferId;
    }
}