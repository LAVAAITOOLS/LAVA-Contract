// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RescueETH(address indexed to, uint256 amount);
    event RescueERC20(address indexed token, address indexed to, uint256 amount);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract LAVA is Context, IERC20, Ownable {
    string private constant _name = "LAVA";
    string private constant _symbol = "LAVA";
    uint8 private constant _decimals = 18;

    uint256 private constant _totalSupply = 50_000_000 * 10**_decimals; // 50M

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // --- Trading control ---
    bool public tradingEnabled = false;
    uint256 public tradingStartTimestamp; // set when enableTrading() called

    // --- AMM pairs detection ---
    mapping(address => bool) public automatedMarketMakerPairs;

    // --- Fee timing & immutable fee values ---
    uint16 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant INITIAL_FEE_PERIOD = 90 days;
    uint16 private constant INITIAL_FEE_BPS = 250; // 2.5% during first 90 days
    uint16 private constant POST_FEE_BPS = 100; // 1.0% after 90 days

    // Treasury wallet for fee collection
    address public treasuryWallet;
    uint256 public feeTransferThreshold; // Threshold for transferring fees to treasury
    uint256 public collectedFees; // Track fees collected in contract

    uint public constant privateSaleShare = 900; // 9%
    uint public constant publicSaleShare = 2000; // 20%
    uint public constant liquidityProvisionShare = 600; // 6%
    uint public constant communityShare = 4000; // 40%
    uint public constant cexListingShare = 1000; // 10%
    uint public constant advisorShare = 800; // 8%
    uint public constant teamShare = 700; // 7%

    // Non-vesting wallets (tokens minted immediately at deployment)
    address public liquidityProvisionWallet;
    address public publicSaleWallet;

    // TGE and Vesting tracking
    uint256 public immutable tgeTimestamp; // Set at deployment (TGE)
    uint256 public constant WEEK_IN_SECONDS = 7 days;

    // Vesting categories
    enum VestingCategory { PrivateSale, CommunityRewards, Advisors, CexListing, Team }

    // Vesting configuration struct
    struct VestingSchedule {
        uint256 totalShare;        // basis points of total supply (e.g., 600 = 6%)
        uint256 tgePercent;        // basis points of category allocation released at TGE
        uint256 weeklyPercent;     // basis points of category allocation released weekly
        uint256 vestingWeeks;      // number of weeks after TGE for weekly releases
        uint256 released;          // tokens already released
        address wallet;            // destination wallet
    }

    // Vesting schedules for each category
    mapping(VestingCategory => VestingSchedule) public vestingSchedules;

    // Minting tracking
    uint256 public totalMinted = 0;
    mapping(VestingCategory => uint256) public mintedByCategory;

    // Fee transfer lock to prevent reentrancy
    bool private inFeeTransfer;
    modifier lockFeeTransfer() {
        inFeeTransfer = true;
        _;
        inFeeTransfer = false;
    }
    uint256 public constant TEMP_LIMIT_WINDOW = 1 minutes; // first 1 minute
    uint256 public constant TEMP_MAX_BPS = 50; // 0.5% = 50 bps
    bool public limitsInEffect = true; // enforced only during the TEMP_LIMIT_WINDOW

    event TradingEnabled(uint256 startTimestamp);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeeTransferThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event FeesTransferredToTreasury(uint256 amount);
    event VestingWalletsUpdated(
        address privateSale,
        address publicSale, 
        address liquidityProvision,
        address communityRewards,
        address cexListing,
        address advisor,
        address team
    );
    event TokensReleased(VestingCategory indexed category, address indexed wallet, uint256 amount, uint256 totalReleased);
    event VestingScheduleUpdated(VestingCategory indexed category, uint256 totalShare, uint256 tgePercent, uint256 weeklyPercent, uint256 vestingWeeks);

    constructor(
        address _treasuryWallet,
        address _liquidityWallet,
        address _publicSaleWallet
    ) Ownable() {
        require(_treasuryWallet != address(0), "treasury 0");
        require(_liquidityWallet != address(0), "liquidity 0");
        require(_publicSaleWallet != address(0), "public sale 0");

        treasuryWallet = _treasuryWallet;
        liquidityProvisionWallet = _liquidityWallet;
        publicSaleWallet = _publicSaleWallet;
        
        // Set default fee transfer threshold to 0.1% of total supply
        feeTransferThreshold = (_totalSupply * 10) / 10000;

        tgeTimestamp = block.timestamp;

        _initializeVestingSchedules();

        uint256 liquidityAmount = (_totalSupply * liquidityProvisionShare) / FEE_DENOMINATOR;
        
        uint256 publicSaleAmount = (_totalSupply * publicSaleShare) / FEE_DENOMINATOR;
        
        _mint(_liquidityWallet, liquidityAmount);
        
        _mint(_publicSaleWallet, publicSaleAmount);
    }

    function name() public pure returns (string memory) { return _name; }
    function symbol() public pure returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return totalMinted; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "approve owner 0");
        require(spender != address(0), "approve spender 0");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "mint to zero address");
        require(amount > 0, "mint zero amount");
        
        // Check total supply limit
        require(totalMinted + amount <= _totalSupply, "Exceeds total supply");
        
        // Update total minted
        totalMinted += amount;
        
        // Update balance and emit transfer
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "zero addr");
        require(_balances[from] >= amount, "insufficient balance");

        // trading guard
        if (!tradingEnabled) {
            // Only owner may move tokens before trading enabled (adding liquidity, team ops)
            require(from == owner() || to == owner(), "Trading is not enabled");
        }

        // Temporary limits: enforced only during the first 1 minute after trading enabled
        if (tradingEnabled && limitsInEffect && block.timestamp <= tradingStartTimestamp + TEMP_LIMIT_WINDOW) {
            uint256 maxAllowed = (_totalSupply * TEMP_MAX_BPS) / FEE_DENOMINATOR; // 0.5% of total supply
            if (automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]) { // buy or sell
                require(amount <= maxAllowed, "temp limit: exceeds max allowed (0.5% total supply)");
            }
        }

        // Check if we should transfer collected fees to treasury
        uint256 contractTokenBalance = _balances[address(this)];
        if (contractTokenBalance >= feeTransferThreshold && !inFeeTransfer && from != address(this) && to != address(this)) {
            _transferFeesToTreasury();
        }

        uint256 amountReceived = amount;
        if ((automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]) && !_isFeeExcluded(from, to)) {
            uint16 feeBps = _currentFeeBps();
            uint256 feeAmount = (amount * feeBps) / FEE_DENOMINATOR;
            if (feeAmount > 0) {
                amountReceived = amount - feeAmount;
                _balances[address(this)] += feeAmount;
                collectedFees += feeAmount;
                emit Transfer(from, address(this), feeAmount);
            }
        }

        _balances[from] -= amount;
        _balances[to] += amountReceived;
        emit Transfer(from, to, amountReceived);
    }

    function _isFeeExcluded(address from, address to) internal view returns (bool) {
        if (from == owner() || to == owner() || from == address(this) || to == address(this)) return true;
        return false;
    }

    function _currentFeeBps() internal view returns (uint16) {
        if (!tradingEnabled) return 0;
        if (block.timestamp < tradingStartTimestamp + INITIAL_FEE_PERIOD) return INITIAL_FEE_BPS;
        return POST_FEE_BPS;
    }

    function _transferFeesToTreasury() internal lockFeeTransfer {
        uint256 contractBalance = _balances[address(this)];
        if (contractBalance == 0) return;
        
        _balances[address(this)] = 0;
        _balances[treasuryWallet] += contractBalance;
        collectedFees = 0;
        
        emit Transfer(address(this), treasuryWallet, contractBalance);
        emit FeesTransferredToTreasury(contractBalance);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "already enabled");
        tradingEnabled = true;
        tradingStartTimestamp = block.timestamp;
        emit TradingEnabled(tradingStartTimestamp);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != address(0), "pair 0");
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyOwner {
        require(_treasuryWallet != address(0), "treasury wallet cannot be zero");
        address oldWallet = treasuryWallet;
        treasuryWallet = _treasuryWallet;
        emit TreasuryWalletUpdated(oldWallet, _treasuryWallet);
    }

    function setFeeTransferThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "threshold must be greater than 0");
        uint256 oldThreshold = feeTransferThreshold;
        feeTransferThreshold = _threshold;
        emit FeeTransferThresholdUpdated(oldThreshold, _threshold);
    }

    function setPrivateSaleWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        vestingSchedules[VestingCategory.PrivateSale].wallet = _wallet;
    }

    function setPublicSaleWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        publicSaleWallet = _wallet;
    }

    function setLiquidityProvisionWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        liquidityProvisionWallet = _wallet;
    }

    function setCommunityRewardsWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        vestingSchedules[VestingCategory.CommunityRewards].wallet = _wallet;
    }

    function setCexListingWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        vestingSchedules[VestingCategory.CexListing].wallet = _wallet;
    }

    function setAdvisorWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        vestingSchedules[VestingCategory.Advisors].wallet = _wallet;
    }

    function setTeamWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        vestingSchedules[VestingCategory.Team].wallet = _wallet;
    }

    

    function manualTransferFeesToTreasury() external onlyOwner {
        require(_balances[address(this)] > 0, "No fees to transfer");
        _transferFeesToTreasury();
    }

    function disableTemporaryLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function rescueETH(address to) external onlyOwner {
        require(to != address(0), "zero addr");
        uint256 bal = address(this).balance;
        (bool success, ) = payable(to).call{value: bal}("");
        require(success, "ETH transfer failed");
        emit RescueETH(to, bal);
    }

    function rescueERC20(address tokenAddress, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero addr");
        bool ok = IERC20(tokenAddress).transfer(to, amount);
        require(ok, "ERC20 transfer failed");
        emit RescueERC20(tokenAddress, to, amount);
    }

    function _initializeVestingSchedules() internal {
        vestingSchedules[VestingCategory.PrivateSale] = VestingSchedule({
            totalShare: privateSaleShare,      // 900 (9%)
            tgePercent: 2500,                  // 25%
            weeklyPercent: 2500,               // 25%
            vestingWeeks: 3,                   // 3 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        vestingSchedules[VestingCategory.CommunityRewards] = VestingSchedule({
            totalShare: communityShare,        // 4000 (40%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 1150,                // 5% monthly = 1150 bps weekly (5000/4.345)
            vestingWeeks: 86,                  // 20 months = 86 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        vestingSchedules[VestingCategory.Advisors] = VestingSchedule({
            totalShare: advisorShare,          // 800 (8%)
            tgePercent: 2500,                  // 25%
            weeklyPercent: 2500,               // 25%
            vestingWeeks: 3,                   // 3 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        vestingSchedules[VestingCategory.CexListing] = VestingSchedule({
            totalShare: cexListingShare,       // 1000 (10%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 192,                // 25% quarterly = ~192 bps weekly (2500/13)
            vestingWeeks: 52,                  // 4 quarters = ~52 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        vestingSchedules[VestingCategory.Team] = VestingSchedule({
            totalShare: teamShare,             // 700 (7%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 230,                // 10% monthly = ~230 bps weekly (1000/4.33)
            vestingWeeks: 56,                  // 10 months = ~56 weeks (starts after 13 week cliff)
            released: 0,
            wallet: address(0)                 // Set later
        });
    }


    function releaseTokens(VestingCategory category) external returns (uint256 amount) {
        VestingSchedule storage schedule = vestingSchedules[category];
        require(schedule.wallet != address(0), "Wallet not set for category");
        
        uint256 vestedAmount = calculateVested(category);
        require(vestedAmount > schedule.released, "No tokens to release");
        
        amount = vestedAmount - schedule.released;
        
        uint256 totalCategoryTokens = (_totalSupply * schedule.totalShare) / FEE_DENOMINATOR;
        require(mintedByCategory[category] + amount <= totalCategoryTokens, "Exceeds category allocation");
        
        schedule.released = vestedAmount;
        
        _mint(schedule.wallet, amount);
        
        mintedByCategory[category] += amount;
        
        emit TokensReleased(category, schedule.wallet, amount, schedule.released);
        
        return amount;
    }
    
    function calculateVested(VestingCategory category) public view returns (uint256 vestedAmount) {
        VestingSchedule memory schedule = vestingSchedules[category];
        uint256 totalCategoryTokens = (_totalSupply * schedule.totalShare) / FEE_DENOMINATOR;
        uint256 remainingCategoryTokens = totalCategoryTokens - mintedByCategory[category];
        uint256 timeSinceTGE = block.timestamp - tgeTimestamp;

        // Handle team cliff period - no accumulation during cliff
        if (category == VestingCategory.Team) {
            uint256 cliffWeeks = 13; // 3 months cliff
            if (timeSinceTGE < cliffWeeks * WEEK_IN_SECONDS) {
                return 0; // Still in cliff period - no tokens accumulated yet
            }
            
            // For team, calculate weeks passed since cliff ended, not since TGE
            uint256 timeSinceCliffEnd = timeSinceTGE - (cliffWeeks * WEEK_IN_SECONDS);
            uint256 weeksSinceCliffEnd = timeSinceCliffEnd / WEEK_IN_SECONDS;
            
            // Team has no TGE release, only weekly releases after cliff
            vestedAmount = 0;
            
            if (weeksSinceCliffEnd > 0 && schedule.weeklyPercent > 0) {
                uint256 weeksToCalculate = weeksSinceCliffEnd > schedule.vestingWeeks ? schedule.vestingWeeks : weeksSinceCliffEnd;
                uint256 weeklyAmount = (totalCategoryTokens * schedule.weeklyPercent) / FEE_DENOMINATOR;
                vestedAmount = weeklyAmount * weeksToCalculate;
            }
        } else {
            // Standard vesting logic for non-team categories
            // TGE release
            uint256 tgeAmount = (totalCategoryTokens * schedule.tgePercent) / FEE_DENOMINATOR;
            vestedAmount = tgeAmount;

            uint256 weeksPassed = timeSinceTGE / WEEK_IN_SECONDS;
            if (weeksPassed > 0 && schedule.weeklyPercent > 0) {
                uint256 weeksToCalculate = weeksPassed > schedule.vestingWeeks ? schedule.vestingWeeks : weeksPassed;
                uint256 weeklyAmount = (totalCategoryTokens * schedule.weeklyPercent) / FEE_DENOMINATOR;
                vestedAmount += weeklyAmount * weeksToCalculate;
            }
        }
        
        if (vestedAmount > remainingCategoryTokens) {
            vestedAmount = remainingCategoryTokens;
        }
        
        return vestedAmount;
    }
    function getAvailableToRelease(VestingCategory category) external view returns (uint256 availableAmount) {
        VestingSchedule memory schedule = vestingSchedules[category];
        uint256 vestedAmount = calculateVested(category);
        if (vestedAmount > schedule.released) {
            availableAmount = vestedAmount - schedule.released;
        }
        return availableAmount;
    }


    function setVestingWallet(VestingCategory category, address wallet) external onlyOwner {
        require(wallet != address(0), "wallet 0");
        vestingSchedules[category].wallet = wallet;
    }

    function maxTotalSupply() public pure returns (uint256) {
        return _totalSupply;
    }

    function remainingSupply() public view returns (uint256) {
        return _totalSupply - totalMinted;
    }

    function getMintedByCategory(VestingCategory category) public view returns (uint256) {
        return mintedByCategory[category];
    }

    function getRemainingCategoryAllocation(VestingCategory category) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[category];
        uint256 totalCategoryTokens = (_totalSupply * schedule.totalShare) / FEE_DENOMINATOR;
        return totalCategoryTokens - mintedByCategory[category];
    }
    
    // View functions for treasury and fee information
    function getCollectedFees() external view returns (uint256) {
        return collectedFees;
    }
    
    function getContractTokenBalance() external view returns (uint256) {
        return _balances[address(this)];
    }
    
    // Getter functions for vesting wallet addresses
    function privateSaleWallet() external view returns (address) {
        return vestingSchedules[VestingCategory.PrivateSale].wallet;
    }
    
    // publicSaleWallet is already a public state variable, no need for getter
    
    function communityRewardsWallet() external view returns (address) {
        return vestingSchedules[VestingCategory.CommunityRewards].wallet;
    }
    
    function cexListingWallet() external view returns (address) {
        return vestingSchedules[VestingCategory.CexListing].wallet;
    }
    
    function advisorWallet() external view returns (address) {
        return vestingSchedules[VestingCategory.Advisors].wallet;
    }
    
    function teamWallet() external view returns (address) {
        return vestingSchedules[VestingCategory.Team].wallet;
    }
}
