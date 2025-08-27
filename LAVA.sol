// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * LAVA Token (Base) - ERC20
 *
 * Finalized contract per owner specifications:
 * - Fixed total supply: 250,000,000 LAVA (immutable, no mint).
 * - No burn function.
 * - Trading tax: 2.5% buy / 2.5% sell for the first 90 days after trading enabled;
 *   permanently drops to 1.0% buy / 1.0% sell after 90 days.
 *   >> Fees are hardcoded and cannot be changed by the owner.
 * - No transfer tax (peer-to-peer transfers are fee-free).
 * - Owner remains (for IDO admin tasks). No forced renounce by contract.
 * - Liquidity locking is off-chain (handled by the team / launchpad).
 * - No blacklist.
 * - No emergency pause.
 * - Temporary anti-snipe limit: for the first 1 minute after trading is enabled,
 *   max buy or sell per transaction = 0.5% of total supply. After 1 minute, limits clear.
 * - Minimal admin surface: owner can set AMM pairs, router, fee-share wallets, swap thresholds, and enable trading.
 *
 * Security notes & rationale:
 * - Fee schedule and limit windows are enforced by block timestamps and constants in-code.
 * - SwapBack uses a reentrancy guard (lockTheSwap modifier).
 * - The contract avoids owner-controlled mutable fee rates to reduce rug risk.
 * - Owner retains minimal controls needed for an IDO workflow (pair setting, router, wallets).
 *
 * Auditor checklist (quick):
 * - Confirm router address and pair addresses before deployment.
 * - Confirm marketing & buyback wallets set correctly post-deploy.
 * - Test trading enable flow, 1-minute limit, and 90-day fee reduction behavior on a testnet fork.
 *
 * DISCLAIMER: Please audit before mainnet deployment.
 */

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

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

    uint256 private constant _totalSupply = 250_000_000 * 10**_decimals; // 250M

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // --- Trading control ---
    bool public tradingEnabled = false;
    uint256 public tradingStartTimestamp; // set when enableTrading() called

    // --- AMM pairs detection ---
    mapping(address => bool) public automatedMarketMakerPairs;
    address public routerAddress;

    // --- Fee timing & immutable fee values ---
    uint16 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant INITIAL_FEE_PERIOD = 90 days;
    uint16 private constant INITIAL_FEE_BPS = 250; // 2.5% during first 90 days
    uint16 private constant POST_FEE_BPS = 100; // 1.0% after 90 days

    // Fee split (in bps of the fee amount) configurable by owner to route funds
    uint16 public liquidityShareBps = 3000; // 30% of fee
    uint16 public marketingShareBps = 5000; // 50% of fee
    uint16 public buybackShareBps = 2000; // 20% of fee

    address public marketingWallet;
    address public buybackWallet;

    // Collected fee tokens stored in contract
    uint256 public tokensForLiquidity;
    uint256 public tokensForMarketing;
    uint256 public tokensForBuyback;

    uint public constant privateSaleShare = 600; // 6%
    uint public constant publicSaleShare = 2000; // 20%
    uint public constant liquidityProvisionShare = 300; // 3%
    uint public constant communityShare = 4600; // 46%
    uint public constant cexListingShare = 1000; // 10%
    uint public constant advisorShare = 800; // 8%
    uint public constant teamShare = 700; // 7%

    // Vesting wallet addresses
    address public privateSaleWallet;
    address public publicSaleWallet;
    address public liquidityProvisionWallet;
    address public communityRewardsWallet;
    address public cexListingWallet;
    address public advisorWallet;
    address public teamWallet;

    // TGE and Vesting tracking
    uint256 public immutable tgeTimestamp; // Set at deployment (TGE)
    uint256 public constant WEEK_IN_SECONDS = 7 days;

    // Vesting categories
    enum VestingCategory { PrivateSale, PublicSale, CommunityRewards, Advisors, CexListing, Team }

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

    // Swap settings
    bool private inSwap;
    uint256 public swapTokensAtAmount = (_totalSupply * 5) / 10000; // 0.05% default
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // Temporary max tx limits
    uint256 public constant TEMP_LIMIT_WINDOW = 1 minutes; // first 1 minute
    uint256 public constant TEMP_MAX_BPS = 50; // 0.5% = 50 bps
    bool public limitsInEffect = true; // enforced only during the TEMP_LIMIT_WINDOW

    event TradingEnabled(uint256 startTimestamp);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event UpdateFeeShares(uint16 liq, uint16 mkt, uint16 buyback);
    event SwapBack(uint256 tokensSwapped);
    event VestingWalletsUpdated(
        address privateSale,
        address publicSale, 
        address liquidityProvision,
        address communityRewards,
        address cexListing,
        address advisor,
        address team
    );
    event PrivateSaleTokensReleased(address indexed wallet, uint256 amount, uint256 totalReleased);
    event PublicSaleTokensReleased(address indexed wallet, uint256 amount, uint256 totalReleased);
    event TokensReleased(VestingCategory indexed category, address indexed wallet, uint256 amount, uint256 totalReleased);
    event VestingScheduleUpdated(VestingCategory indexed category, uint256 totalShare, uint256 tgePercent, uint256 weeklyPercent, uint256 vestingWeeks);

    constructor(
        address _routerAddress, 
        address _marketingWallet, 
        address _buybackWallet,
        address _liquidityWallet
    ) Ownable() {
        require(_routerAddress != address(0), "router 0");
        require(_marketingWallet != address(0), "marketing 0");
        require(_buybackWallet != address(0), "buyback 0");
        require(_liquidityWallet != address(0), "liquidity 0");

        routerAddress = _routerAddress;
        marketingWallet = _marketingWallet;
        buybackWallet = _buybackWallet;
        liquidityProvisionWallet = _liquidityWallet;
        
        // Set TGE timestamp at deployment
        tgeTimestamp = block.timestamp;

        // Initialize vesting schedules
        _initializeVestingSchedules();

        // Calculate liquidity allocation (3% of total supply)
        uint256 liquidityAmount = (_totalSupply * liquidityProvisionShare) / FEE_DENOMINATOR;
        
        // Transfer liquidity tokens directly to liquidity wallet (no vesting)
        _balances[_liquidityWallet] = liquidityAmount;
        emit Transfer(address(0), _liquidityWallet, liquidityAmount);
        
        // Remaining tokens go to deployer for vesting distribution
        uint256 remainingTokens = _totalSupply - liquidityAmount;
        _balances[_msgSender()] = remainingTokens;
        emit Transfer(address(0), _msgSender(), remainingTokens);
    }

    // --- ERC20 ---
    function name() public pure returns (string memory) { return _name; }
    function symbol() public pure returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public pure override returns (uint256) { return _totalSupply; }
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

    // --- Core transfer with fee logic ---
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

        uint256 contractTokenBalance = _balances[address(this)];
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (canSwap && !inSwap && !automatedMarketMakerPairs[from] && from != address(this) && to != address(this)) {
            _swapBack(contractTokenBalance);
        }

        uint256 amountReceived = amount;
        // apply fee only on trades (buy or sell)
        if ((automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]) && !_isFeeExcluded(from, to)) {
            uint16 feeBps = _currentFeeBps();
            uint256 feeAmount = (amount * feeBps) / FEE_DENOMINATOR;
            if (feeAmount > 0) {
                amountReceived = amount - feeAmount;
                _balances[address(this)] += feeAmount;
                // allocate portions
                tokensForLiquidity += (feeAmount * liquidityShareBps) / FEE_DENOMINATOR;
                tokensForMarketing += (feeAmount * marketingShareBps) / FEE_DENOMINATOR;
                tokensForBuyback += (feeAmount * buybackShareBps) / FEE_DENOMINATOR;
                emit Transfer(from, address(this), feeAmount);
            }
        }

        // perform transfer
        _balances[from] -= amount;
        _balances[to] += amountReceived;
        emit Transfer(from, to, amountReceived);
    }

    function _isFeeExcluded(address from, address to) internal view returns (bool) {
        // Owner and contract are excluded from fees
        if (from == owner() || to == owner() || from == address(this) || to == address(this)) return true;
        return false;
    }

    function _currentFeeBps() internal view returns (uint16) {
        if (!tradingEnabled) return 0;
        if (block.timestamp < tradingStartTimestamp + INITIAL_FEE_PERIOD) return INITIAL_FEE_BPS;
        return POST_FEE_BPS;
    }

    // --- Swap & Liquify ---
    function _swapBack(uint256 contractTokenBalance) internal lockTheSwap {
        uint256 totalTokensToSwap = tokensForLiquidity + tokensForMarketing + tokensForBuyback;
        if (totalTokensToSwap == 0 || contractTokenBalance == 0) { return; }

        if (contractTokenBalance > totalTokensToSwap) contractTokenBalance = totalTokensToSwap;

        uint256 liquidityTokens = (contractTokenBalance * tokensForLiquidity) / totalTokensToSwap / 2;
        uint256 amountToSwapForETH = contractTokenBalance - liquidityTokens;

        uint256 initialETHBalance = address(this).balance;

        _approve(address(this), routerAddress, amountToSwapForETH);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router(routerAddress).WETH();

        IUniswapV2Router(routerAddress).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwapForETH,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethReceived = address(this).balance - initialETHBalance;

        uint256 ethForMarketing = (ethReceived * tokensForMarketing) / totalTokensToSwap;
        uint256 ethForBuyback = (ethReceived * tokensForBuyback) / totalTokensToSwap;
        uint256 ethForLiquidity = ethReceived - ethForMarketing - ethForBuyback;

        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForBuyback = 0;

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            _approve(address(this), routerAddress, liquidityTokens);
            IUniswapV2Router(routerAddress).addLiquidityETH{value: ethForLiquidity}(
                address(this),
                liquidityTokens,
                0,
                0,
                owner(),
                block.timestamp
            );
        }

        (bool successMarketing, ) = marketingWallet.call{value: ethForMarketing}("");
        (bool successBuyback, ) = buybackWallet.call{value: ethForBuyback}("");

        emit SwapBack(contractTokenBalance);
    }

    // --- Admin ---
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

    function setRouterAddress(address _router) external onlyOwner {
        require(_router != address(0), "router 0");
        routerAddress = _router;
    }

    function setFeeShares(uint16 _liqShareBps, uint16 _marketingShareBps, uint16 _buybackShareBps) external onlyOwner {
        require(_liqShareBps + _marketingShareBps + _buybackShareBps == FEE_DENOMINATOR, "shares must sum to 10000");
        liquidityShareBps = _liqShareBps;
        marketingShareBps = _marketingShareBps;
        buybackShareBps = _buybackShareBps;
        emit UpdateFeeShares(_liqShareBps, _marketingShareBps, _buybackShareBps);
    }

    function setWallets(address _marketing, address _buyback) external onlyOwner {
        require(_marketing != address(0) && _buyback != address(0), "wallet 0");
        marketingWallet = _marketing;
        buybackWallet = _buyback;
    }

    // Set individual vesting wallets
    function setPrivateSaleWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        privateSaleWallet = _wallet;
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
        communityRewardsWallet = _wallet;
    }

    function setCexListingWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        cexListingWallet = _wallet;
    }

    function setAdvisorWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        advisorWallet = _wallet;
    }

    function setTeamWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "wallet 0");
        teamWallet = _wallet;
    }

    // Set all vesting wallets at once
    function setVestingWallets(
        address _privateSale,
        address _publicSale,
        address _liquidityProvision,
        address _communityRewards,
        address _cexListing,
        address _advisor,
        address _team
    ) external onlyOwner {
        require(
            _privateSale != address(0) &&
            _publicSale != address(0) &&
            _liquidityProvision != address(0) &&
            _communityRewards != address(0) &&
            _cexListing != address(0) &&
            _advisor != address(0) &&
            _team != address(0),
            "wallet 0"
        );
        
        privateSaleWallet = _privateSale;
        publicSaleWallet = _publicSale;
        liquidityProvisionWallet = _liquidityProvision;
        communityRewardsWallet = _communityRewards;
        cexListingWallet = _cexListing;
        advisorWallet = _advisor;
        teamWallet = _team;
        
        emit VestingWalletsUpdated(
            _privateSale,
            _publicSale,
            _liquidityProvision,
            _communityRewards,
            _cexListing,
            _advisor,
            _team
        );
    }

    function setSwapSettings(uint256 _swapTokensAtAmount) external onlyOwner {
        require(_swapTokensAtAmount > 0, "zero");
        swapTokensAtAmount = _swapTokensAtAmount;
    }

    function disableTemporaryLimits() external onlyOwner {
        limitsInEffect = false;
    }

    // emergency rescue (owner only) - minimal surface
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

    /**
     * @dev Initialize vesting schedules for all categories
     */
    function _initializeVestingSchedules() internal {
        // Private Sale: 25% @ TGE, 25% weekly for 3 weeks
        vestingSchedules[VestingCategory.PrivateSale] = VestingSchedule({
            totalShare: privateSaleShare,      // 600 (6%)
            tgePercent: 2500,                  // 25%
            weeklyPercent: 2500,               // 25%
            vestingWeeks: 3,                   // 3 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        // Public Sale: 35% @ TGE, 32.5% weekly for 2 weeks
        vestingSchedules[VestingCategory.PublicSale] = VestingSchedule({
            totalShare: publicSaleShare,       // 2000 (20%)
            tgePercent: 3500,                  // 35%
            weeklyPercent: 3250,               // 32.5%
            vestingWeeks: 2,                   // 2 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        // Community Rewards: 2.5% monthly linear (12 months, no TGE)
        vestingSchedules[VestingCategory.CommunityRewards] = VestingSchedule({
            totalShare: communityShare,        // 4600 (46%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 575,                // 2.5% monthly = 575 bps weekly (2500/4.345)
            vestingWeeks: 52,                  // 12 months = 52 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        // Advisors: 25% @ TGE, 25% weekly linear (assuming same as private sale)
        vestingSchedules[VestingCategory.Advisors] = VestingSchedule({
            totalShare: advisorShare,          // 800 (8%)
            tgePercent: 2500,                  // 25%
            weeklyPercent: 2500,               // 25%
            vestingWeeks: 3,                   // 3 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        // CEX Listing: 25% quarterly linear (assuming 4 quarters, no TGE)
        vestingSchedules[VestingCategory.CexListing] = VestingSchedule({
            totalShare: cexListingShare,       // 1000 (10%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 192,                // 25% quarterly = ~192 bps weekly (2500/13)
            vestingWeeks: 52,                  // 4 quarters = ~52 weeks
            released: 0,
            wallet: address(0)                 // Set later
        });

        // Team: 5 month cliff, 10% monthly linear (assuming 10 months after cliff)
        vestingSchedules[VestingCategory.Team] = VestingSchedule({
            totalShare: teamShare,             // 700 (7%)
            tgePercent: 0,                     // 0% at TGE
            weeklyPercent: 230,                // 10% monthly = ~230 bps weekly (1000/4.33)
            vestingWeeks: 43,                  // 10 months = ~43 weeks (starts after 22 week cliff)
            released: 0,
            wallet: address(0)                 // Set later
        });
    }

    /**
     * @dev Releases vested tokens for a specific category
     * @param category The vesting category to release tokens for
     * @return amount The amount of tokens released
     */
    function releaseTokens(VestingCategory category) external returns (uint256 amount) {
        VestingSchedule storage schedule = vestingSchedules[category];
        require(schedule.wallet != address(0), "Wallet not set for category");
        
        uint256 vestedAmount = calculateVested(category);
        require(vestedAmount > schedule.released, "No tokens to release");
        
        amount = vestedAmount - schedule.released;
        schedule.released = vestedAmount;
        
        // Transfer tokens from contract deployer to category wallet
        _transfer(owner(), schedule.wallet, amount);
        
        emit TokensReleased(category, schedule.wallet, amount, schedule.released);
        
        return amount;
    }
    
    /**
     * @dev Calculates how many tokens should be vested for a category by now
     * @param category The vesting category to calculate for
     * @return vestedAmount Total amount that should be vested
     */
    function calculateVested(VestingCategory category) public view returns (uint256 vestedAmount) {
        VestingSchedule memory schedule = vestingSchedules[category];
        uint256 totalCategoryTokens = (_totalSupply * schedule.totalShare) / FEE_DENOMINATOR;
        
        // Handle team cliff (5 months = ~22 weeks)
        uint256 timeSinceTGE = block.timestamp - tgeTimestamp;

        if (category == VestingCategory.Team) {
            uint256 cliffWeeks = 22; // 5 months cliff
            if (timeSinceTGE < cliffWeeks * WEEK_IN_SECONDS) {
                return 0; // Still in cliff period - no tokens claimable yet
            }
            // After cliff: calculate vesting for ALL weeks since TGE (including cliff period)
        }

        // TGE release
        uint256 tgeAmount = (totalCategoryTokens * schedule.tgePercent) / FEE_DENOMINATOR;
        vestedAmount = tgeAmount;

        // Weekly releases - use full timeSinceTGE (including cliff period for team)
        uint256 weeksPassed = timeSinceTGE / WEEK_IN_SECONDS;
        if (weeksPassed > 0 && schedule.weeklyPercent > 0) {
            uint256 weeksToCalculate = weeksPassed > schedule.vestingWeeks ? schedule.vestingWeeks : weeksPassed;
            uint256 weeklyAmount = (totalCategoryTokens * schedule.weeklyPercent) / FEE_DENOMINATOR;
            vestedAmount += weeklyAmount * weeksToCalculate;
        }
        
        // Cap at total allocation
        if (vestedAmount > totalCategoryTokens) {
            vestedAmount = totalCategoryTokens;
        }
        
        return vestedAmount;
    }
    
    /**
     * @dev View function to check how many tokens are available to release for a category
     * @param category The vesting category to check
     * @return availableAmount Tokens ready to be released
     */
    function getAvailableToRelease(VestingCategory category) external view returns (uint256 availableAmount) {
        VestingSchedule memory schedule = vestingSchedules[category];
        uint256 vestedAmount = calculateVested(category);
        if (vestedAmount > schedule.released) {
            availableAmount = vestedAmount - schedule.released;
        }
        return availableAmount;
    }

    // Set individual vesting wallets
    function setVestingWallet(VestingCategory category, address wallet) external onlyOwner {
        require(wallet != address(0), "wallet 0");
        vestingSchedules[category].wallet = wallet;
        
        // Update individual wallet variables for backward compatibility
        if (category == VestingCategory.PrivateSale) privateSaleWallet = wallet;
        else if (category == VestingCategory.PublicSale) publicSaleWallet = wallet;
        else if (category == VestingCategory.CommunityRewards) communityRewardsWallet = wallet;
        else if (category == VestingCategory.Advisors) advisorWallet = wallet;
        else if (category == VestingCategory.CexListing) cexListingWallet = wallet;
        else if (category == VestingCategory.Team) teamWallet = wallet;
    }
}
