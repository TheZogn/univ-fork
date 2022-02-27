// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./OwnerRecoveryUpgradeable.sol";
import "./WindImplementationPointerUpgradeable.sol";
import "./LiquidityPoolManagerImplementationPointerUpgradeable.sol";

contract TurbinesManagerUpgradeable is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    OwnerRecoveryUpgradeable,
    ReentrancyGuardUpgradeable,
    WindImplementationPointerUpgradeable,
    LiquidityPoolManagerImplementationPointerUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct TurbineInfoEntity {
        TurbineEntity turbine;
        uint256 id;
        uint256 pendingRewards;
        uint256 rewardPerDay;
        uint256 compoundDelay;
        uint256 pendingRewardsGross;
        uint256 rewardPerDayGross;
    }

    struct TurbineEntity {
        uint256 id;
        string name;
        uint256 creationTime;
        uint256 lastProcessingTimestamp;
        uint256 rewardMult;
        uint256 turbineValue;
        uint256 totalClaimed;
        bool exists;
        bool isMerged;
    }

    struct TierStorage {
        uint256 rewardMult;
        uint256 amountLockedInTier;
        bool exists;
    }

    CountersUpgradeable.Counter private _turbineCounter;
    mapping(uint256 => TurbineEntity) private _turbines;
    mapping(uint256 => TierStorage) private _tierTracking;
    uint256[] _tiersTracked;

    uint256 public rewardPerDay;
    uint256 public creationMinPrice;
    uint256 public compoundDelay;
    uint256 public processingFee;
    bool public feesLive;
    uint24[6] public tierLevel;
    uint16[6] public tierSlope;

    uint256 private constant ONE_DAY = 86400;
    uint256 public totalValueLocked;

    uint256 public burnedFromRenaming;
    uint256 public burnedFromMerging;

    modifier onlyTurbineOwner() {
        address sender = _msgSender();
        require(
            sender != address(0),
            "Turbines: Cannot be from the zero address"
        );
        require(
            isOwnerOfTurbines(sender),
            "Turbines: No Turbine owned by this account"
        );
        _;
    }


    modifier checkPermissions(uint256 _turbineId) {
        address sender = _msgSender();
        require(turbineExists(_turbineId), "Turbines: This turbine doesn't exist");
        require(
            isApprovedOrOwnerOfTurbine(sender, _turbineId),
            "turbines: You do not have control over this turbine"
        );
        _;
    }

    modifier checkPermissionsMultiple(uint256[] memory _turbineIds) {
        address sender = _msgSender();
        for (uint256 i = 0; i < _turbineIds.length; i++) {
            require(
                turbineExists(_turbineIds[i]),
                "turbines: This turbine doesn't exist"
            );
            require(
                isApprovedOrOwnerOfTurbine(sender, _turbineIds[i]),
                "turbines: You do not control this turbine"
            );
        }
        _;
    }

    modifier verifyName(string memory turbineName) {
        require(
            bytes(turbineName).length > 1 && bytes(turbineName).length < 32,
            "turbines: Incorrect name length, must be between 2 to 31"
        );
        _;
    }

    event Compound(
        address indexed account,
        uint256 indexed turbineId,
        uint256 amountToCompound
    );
    event Cashout(
        address indexed account,
        uint256 indexed turbineId,
        uint256 rewardAmount
    );

    event CompoundAll(
        address indexed account,
        uint256[] indexed affectedTurbines,
        uint256 amountToCompound
    );
    event CashoutAll(
        address indexed account,
        uint256[] indexed affectedTurbines,
        uint256 rewardAmount
    );

    event Create(
        address indexed account,
        uint256 indexed newTurbineId,
        uint256 amount
    );

    event Rename(
        address indexed account,
        string indexed previousName,
        string indexed newName
    );

    event Merge(
        uint256[] indexed turbineIds,
        string indexed name,
        uint256 indexed previousTotalValue
    );

    function initialize() external initializer {
        __ERC721_init("Wind Ecosystem", "TURBINE");
        __Ownable_init();
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        feesLive = false;
        // Initialize contract
        changeNodeMinPrice(42_000 * (10**18)); // 42,000 UNIV
        changeCompoundDelay(14400); // 4h
        changeTierSystem(
            [100000, 105000, 110000, 120000, 130000, 140000],
            [1000, 500, 100, 50, 10, 0]
        );
    }

    function changeFeesLive(bool _feesLive) onlyOwner external{
        feesLive = _feesLive;

    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
        return "Use API";
    }

    function renameTurbine(uint256 _turbineId, string memory turbineName)
        external
        nonReentrant
        onlyTurbineOwner
        checkPermissions(_turbineId)
        whenNotPaused
        verifyName(turbineName)
    {
        address account = _msgSender();
        TurbineEntity storage turbine = _turbines[_turbineId];
        require(turbine.turbineValue > 0, "Error: turbine is empty");
        (uint256 newTurbineValue, uint256 feeAmount) = getPercentageOf(
            turbine.turbineValue,
            1
        );
        logTier(turbine.rewardMult, -int256(feeAmount));
        burnedFromRenaming += feeAmount;
        turbine.turbineValue = newTurbineValue;
        string memory previousName = turbine.name;
        turbine.name = turbineName;
        emit Rename(account, previousName, turbineName);
    }

    function mergeTurbines(uint256[] memory _turbineIds, string memory turbineName)
        external
        nonReentrant
        onlyTurbineOwner
        checkPermissionsMultiple(_turbineIds)
        whenNotPaused
        verifyName(turbineName)
    {
        address account = _msgSender();
        require(
            _turbineIds.length > 1,
            "turbinesManager: At least 2 turbines must be selected in order for the merge to work"
        );

        uint256 lowestTier = 0;
        uint256 totalValue = 0;

        for (uint256 i = 0; i < _turbineIds.length; i++) {
            TurbineEntity storage turbineFromIds = _turbines[_turbineIds[i]];
            require(
                isProcessable(turbineFromIds),
                "turbinesManager: For the process to work, all selected turbines must be compoundable. Try again later."
            );

            // Compound the turbine
            compoundReward(turbineFromIds.id);

            // Use this tier if it's lower than current
            if (lowestTier == 0) {
                lowestTier = turbineFromIds.rewardMult;
            } else if (lowestTier > turbineFromIds.rewardMult) {
                lowestTier = turbineFromIds.rewardMult;
            }

            // Additionate the locked value
            totalValue += turbineFromIds.turbineValue;

            // Burn the turbine permanently
            _burn(turbineFromIds.id);
        }
        require(
            lowestTier >= tierLevel[0],
            "turbinesManager: Something went wrong with the tiers"
        );

        // Burn 2% from the value of across the final amount
        (uint256 newTurbineValue, uint256 feeAmount) = getPercentageOf(
            totalValue,
            2
        );
        burnedFromMerging += feeAmount;

        // Mint the amount to the user
        wind.accountReward(account, newTurbineValue);

        // Create the Turbine (which will burn that amount)
        uint256 currentTurbineId = createTurbineWithTokens(
            turbineName,
            newTurbineValue
        );

        // Set tier, logTier and increase
        TurbineEntity storage turbine = _turbines[currentTurbineId];
        turbine.isMerged = true;
        if (lowestTier != tierLevel[0]) {
            logTier(turbine.rewardMult, -int256(turbine.turbineValue));
            turbine.rewardMult = lowestTier;
            logTier(turbine.rewardMult, int256(turbine.turbineValue));
        }

        emit Merge(_turbineIds, turbineName, totalValue);
    }

    function createTurbineWithTokens(
        string memory turbineName,
        uint256 turbineValue
    ) public whenNotPaused verifyName(turbineName) returns (uint256) {
        address sender = _msgSender();
        require(
            turbineValue >= creationMinPrice,
            "turbines: turbine value set below minimum"
        );
        require(
            isNameAvailable(sender, turbineName),
            "Turbines: Name not available"
        );
        require(
            wind.balanceOf(sender) >= creationMinPrice,
            "turbines: Balance too low for creation"
        );

        // Burn the tokens used to mint the NFT
        wind.accountBurn(sender, turbineValue);

        // Increment the total number of tokens
        _turbineCounter.increment();

        uint256 newTurbineId = _turbineCounter.current();
        uint256 currentTime = block.timestamp;

        // Add this to the TVL
        totalValueLocked += turbineValue;
        logTier(tierLevel[0], int256(turbineValue));

        // Add turbine
        _turbines[newTurbineId] = TurbineEntity({
            id: newTurbineId,
            name: turbineName,
            creationTime: currentTime,
            lastProcessingTimestamp: currentTime,
            rewardMult: tierLevel[0],
            turbineValue: turbineValue,
            totalClaimed: 0,
            exists: true,
            isMerged: false
        });

        // Assign the turbine to this account
        _mint(sender, newTurbineId);

        emit Create(sender, newTurbineId, turbineValue);

        return newTurbineId;
    }

    function cashoutReward(uint256 _turbineId)
        external
        nonReentrant
        onlyTurbineOwner
        checkPermissions(_turbineId)
        whenNotPaused
    {
        address account = _msgSender();
        uint256 amountToReward = _getTurbineCashoutRewards(_turbineId);
        _cashoutReward(amountToReward);

        emit Cashout(account, _turbineId, amountToReward);
    }

    function cashoutAll() external nonReentrant onlyTurbineOwner whenNotPaused {
        address account = _msgSender();
        uint256 rewardsTotal = 0;
        uint256[] memory turbinesOwned = getTurbineIdsOf(account);
        for (uint256 i = 0; i < turbinesOwned.length; i++) {
            uint256 amountToReward = _getTurbineCashoutRewards(turbinesOwned[i]);
            rewardsTotal += amountToReward;
        }
        _cashoutReward(rewardsTotal);

        emit CashoutAll(account, turbinesOwned, rewardsTotal);
    }

    function cashoutRewardNoFees(uint256 _turbineId)
        external
        nonReentrant
        onlyTurbineOwner
        checkPermissions(_turbineId)
        whenNotPaused
    {
        address account = _msgSender();
        uint256 amountToReward = _getTurbineCashoutRewards(_turbineId);
        _cashoutRewardNoFees(amountToReward);

        emit Cashout(account, _turbineId, amountToReward);
    }

    function cashoutAllNoFees() external nonReentrant onlyTurbineOwner whenNotPaused {
        address account = _msgSender();
        uint256 rewardsTotal = 0;
        uint256[] memory turbinesOwned = getTurbineIdsOf(account);
        for (uint256 i = 0; i < turbinesOwned.length; i++) {
            uint256 amountToReward = _getTurbineCashoutRewards(turbinesOwned[i]);
            rewardsTotal += amountToReward;
        }
        _cashoutRewardNoFees(rewardsTotal);

        emit CashoutAll(account, turbinesOwned, rewardsTotal);
    }

    function compoundReward(uint256 _turbineId)
        public
        onlyTurbineOwner
        checkPermissions(_turbineId)
        whenNotPaused
    {
        address account = _msgSender();

        uint256 amountToCompound = _getTurbineCompoundRewards(_turbineId);
        require(
            amountToCompound > 0,
            "turbines: You must wait until you can compound again"
        );
        // à decomenter
        liquidityReward(amountToCompound);

        emit Compound(account, _turbineId, amountToCompound);
    }

    function compoundAll() external nonReentrant onlyTurbineOwner whenNotPaused {
        address account = _msgSender();
        uint256 amountsToCompound = 0;
        uint256[] memory turbinesOwned = getTurbineIdsOf(account);
        uint256[] memory turbinesAffected = new uint256[](turbinesOwned.length);

        for (uint256 i = 0; i < turbinesOwned.length; i++) {
            uint256 amountToCompound = _getTurbineCompoundRewards(
                turbinesOwned[i]
            );
            if (amountToCompound > 0) {
                turbinesAffected[i] = turbinesOwned[i];
                amountsToCompound += amountToCompound;
            } else {
                delete turbinesAffected[i];
            }
        }

        require(amountsToCompound > 0, "turbines: No rewards to compound");
    // à decomenter
        liquidityReward(amountsToCompound);

        emit CompoundAll(account, turbinesAffected, amountsToCompound);
    }

     function compoundAllNoFees() external nonReentrant onlyTurbineOwner whenNotPaused {
        require(feesLive == false, 'Fees are live use function with fees');
        address account = _msgSender();
        uint256 amountsToCompound = 0;
        uint256[] memory turbinesOwned = getTurbineIdsOf(account);
        uint256[] memory turbinesAffected = new uint256[](turbinesOwned.length);

        for (uint256 i = 0; i < turbinesOwned.length; i++) {
            uint256 amountToCompound = _getTurbineCompoundRewards(
                turbinesOwned[i]
            );
            if (amountToCompound > 0) {
                turbinesAffected[i] = turbinesOwned[i];
                amountsToCompound += amountToCompound;
            } else {
                delete turbinesAffected[i];
            }
        }

        require(amountsToCompound > 0, "turbines: No rewards to compound");
    // à decomenter

        emit CompoundAll(account, turbinesAffected, amountsToCompound);
    }

    
    function compoundRewardNoFees(uint256 _turbineId)
        public
        onlyTurbineOwner
        checkPermissions(_turbineId)
        whenNotPaused
    {
        require(feesLive == false, 'Fees are live use function with fees');

        address account = _msgSender();

        uint256 amountToCompound = _getTurbineCompoundRewards(_turbineId);
        require(
            amountToCompound > 0,
            "turbines: You must wait until you can compound again"
        );
        // à decomenter

        emit Compound(account, _turbineId, amountToCompound);
    }

    // Private reward functions

    function _getTurbineCashoutRewards(uint256 _turbineId)
        private
        returns (uint256)
    {
        TurbineEntity storage turbine = _turbines[_turbineId];

        if (!isProcessable(turbine)) {
            return 0;
        }

        uint256 reward = calculateReward(turbine);
        turbine.totalClaimed += reward;

        if (turbine.rewardMult != tierLevel[0]) {
            logTier(turbine.rewardMult, -int256(turbine.turbineValue));
            logTier(tierLevel[0], int256(turbine.turbineValue));
        }

        turbine.rewardMult = tierLevel[0];
        turbine.lastProcessingTimestamp = block.timestamp;

        return reward;
    }

    function _getTurbineCompoundRewards(uint256 _turbineId)
        private
        returns (uint256)
    {
        TurbineEntity storage turbine = _turbines[_turbineId];

        if (!isProcessable(turbine)) {
            return 0;
        }

        uint256 reward = calculateReward(turbine);
        if (reward > 0) {
            totalValueLocked += reward;

            logTier(turbine.rewardMult, -int256(turbine.turbineValue));

            turbine.lastProcessingTimestamp = block.timestamp;
            turbine.turbineValue += reward;
            turbine.rewardMult += increaseMultiplier(turbine.rewardMult);

            logTier(turbine.rewardMult, int256(turbine.turbineValue));
        }
        return reward;
    }

    function _cashoutReward(uint256 amountToReward) private {
        require(
            amountToReward > 0,
            "turbines: You don't have enough reward to cash out"
        );
        address to = _msgSender();
        wind.accountReward(to, amountToReward);

        // Send the minted fee to the contract where liquidity will be added later on
        // a decommenter
        liquidityReward(amountToReward);
    }

    function _cashoutRewardNoFees(uint256 amountToReward) private {
        require(feesLive == false, 'Fees are live use function with fees');
        require(
            amountToReward > 0,
            "turbines: You don't have enough reward to cash out"
        );
        address to = _msgSender();
        wind.accountReward(to, amountToReward);

        // Send the minted fee to the contract where liquidity will be added later on
        // a decommenter
    }

    function logTier(uint256 mult, int256 amount) private {
        TierStorage storage tierStorage = _tierTracking[mult];
        if (tierStorage.exists) {
            require(
                tierStorage.rewardMult == mult,
                "turbines: rewardMult does not match in TierStorage"
            );
            uint256 amountLockedInTier = uint256(
                int256(tierStorage.amountLockedInTier) + amount
            );
            require(
                amountLockedInTier >= 0,
                "turbines: amountLockedInTier cannot underflow"
            );
            tierStorage.amountLockedInTier = amountLockedInTier;
        } else {
            // Tier isn't registered exist, register it
            require(
                amount > 0,
                "turbines: Fatal error while creating new TierStorage. Amount cannot be below zero."
            );
            _tierTracking[mult] = TierStorage({
                rewardMult: mult,
                amountLockedInTier: uint256(amount),
                exists: true
            });
            _tiersTracked.push(mult);
        }
    }

    // Private view functions

    function getPercentageOf(uint256 rewardAmount, uint256 _feeAmount)
        private
        pure
        returns (uint256, uint256)
    {
        uint256 feeAmount = 0;
        if (_feeAmount > 0) {
            feeAmount = (rewardAmount * _feeAmount) / 100;
        }
        return (rewardAmount - feeAmount, feeAmount);
    }

    function increaseMultiplier(uint256 prevMult)
        private
        view
        returns (uint256)
    {
        if (prevMult >= tierLevel[5]) {
            return tierSlope[5];
        } else if (prevMult >= tierLevel[4]) {
            return tierSlope[4];
        } else if (prevMult >= tierLevel[3]) {
            return tierSlope[3];
        } else if (prevMult >= tierLevel[2]) {
            return tierSlope[2];
        } else if (prevMult >= tierLevel[1]) {
            return tierSlope[1];
        } else {
            return tierSlope[0];
        }
    }

    function getTieredRevenues(uint256 mult) private view returns (uint256) {
        // 1% is 11574
        if (mult >= tierLevel[4]) {
            // Sun 2.16%
            return 24999;
        } else if (mult >= tierLevel[3]) {
            // Jupiter 2.13%
            return 24652;
        } else if (mult >= tierLevel[2]) {
            // Neptune 2.10%
            return 24305;
        } else if (mult >= tierLevel[1]) {
            // Earth 2.01%
            return 23263;
        } else if (mult > tierLevel[0]) {
            // Mars 1.8%
            return 20833;
        } else {
            // Mercury 1.74%
            return 20138;
        }
    }

    function isProcessable(TurbineEntity memory turbine)
        private
        view
        returns (bool)
    {
        return
            block.timestamp >= turbine.lastProcessingTimestamp + compoundDelay;
    }

    function calculateReward(TurbineEntity memory turbine)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                turbine.turbineValue,
                turbine.rewardMult,
                block.timestamp - turbine.lastProcessingTimestamp
            );
    }

    function rewardPerDayFor(TurbineEntity memory turbine)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                turbine.turbineValue,
                turbine.rewardMult,
                ONE_DAY
            );
    }

    function _calculateRewardsFromValue(
        uint256 _turbineValue,
        uint256 _rewardMult,
        uint256 _timeRewards
    ) private view returns (uint256) {
        uint256 rewards = (_timeRewards * getTieredRevenues(_rewardMult)) /
            1000000;
        uint256 rewardsMultiplicated = (rewards * _rewardMult) / 100000;
        return (rewardsMultiplicated * _turbineValue) / 100000;
    }

    function turbineExists(uint256 _turbineId) private view returns (bool) {
        require(_turbineId > 0, "turbines: Id must be higher than zero");
        TurbineEntity memory turbine = _turbines[_turbineId];
        if (turbine.exists) {
            return true;
        }
        return false;
    }

    // Public view functions

    function calculateTotalDailyEmission() external view returns (uint256) {
        uint256 dailyEmission = 0;
        for (uint256 i = 0; i < _tiersTracked.length; i++) {
            TierStorage memory tierStorage = _tierTracking[_tiersTracked[i]];
            dailyEmission += _calculateRewardsFromValue(
                tierStorage.amountLockedInTier,
                tierStorage.rewardMult,
                ONE_DAY
            );
        }
        return dailyEmission;
    }

    function isNameAvailable(address account, string memory turbineName)
        public
        view
        returns (bool)
    {
        uint256[] memory turbinesOwned = getTurbineIdsOf(account);
        for (uint256 i = 0; i < turbinesOwned.length; i++) {
            TurbineEntity memory turbine = _turbines[turbinesOwned[i]];
            if (keccak256(bytes(turbine.name)) == keccak256(bytes(turbineName))) {
                return false;
            }
        }
        return true;
    }

    function isOwnerOfTurbines(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    function isApprovedOrOwnerOfTurbine(address account, uint256 _turbineId)
        public
        view
        returns (bool)
    {
        return _isApprovedOrOwner(account, _turbineId);
    }

    function getTurbineIdsOf(address account)
        public
        view
        returns (uint256[] memory)
    {
        uint256 numberOfTurbines = balanceOf(account);
        uint256[] memory turbineIds = new uint256[](numberOfTurbines);
        for (uint256 i = 0; i < numberOfTurbines; i++) {
            uint256 turbineId = tokenOfOwnerByIndex(account, i);
            require(
                turbineExists(turbineId),
                "turbines: This turbine doesn't exist"
            );
            turbineIds[i] = turbineId;
        }
        return turbineIds;
    }

    function getTurbinesByIds(uint256[] memory _turbineIds)
        external
        view
        returns (TurbineInfoEntity[] memory)
    {
        TurbineInfoEntity[] memory turbinesInfo = new TurbineInfoEntity[](
            _turbineIds.length
        );

        for (uint256 i = 0; i < _turbineIds.length; i++) {
            uint256 turbineId = _turbineIds[i];
            TurbineEntity memory turbine = _turbines[turbineId];
            uint256 amountToReward = calculateReward(turbine);
            uint256 amountToRewardDaily = rewardPerDayFor(turbine);
            turbinesInfo[i] = TurbineInfoEntity(
                turbine,
                turbineId,
                amountToReward,
                amountToRewardDaily,
                compoundDelay,
                0,
                0
            );
        }
        return turbinesInfo;
    }

    // Owner functions

    function changeNodeMinPrice(uint256 _creationMinPrice) public onlyOwner {
        require(
            _creationMinPrice > 0,
            "turbines: Minimum price to create a turbine must be above 0"
        );
        creationMinPrice = _creationMinPrice;
    }

    function changeCompoundDelay(uint256 _compoundDelay) public onlyOwner {
        require(
            _compoundDelay > 0,
            "turbines: compoundDelay must be greater than 0"
        );
        compoundDelay = _compoundDelay;
    }

    function changeTierSystem(
        uint24[6] memory _tierLevel,
        uint16[6] memory _tierSlope
    ) public onlyOwner {
        require(
            _tierLevel.length == 6,
            "turbines: newTierLevels length has to be 6"
        );
        require(
            _tierSlope.length == 6,
            "turbines: newTierSlopes length has to be 6"
        );
        tierLevel = _tierLevel;
        tierSlope = _tierSlope;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function burn(uint256 _turbineId)
        external
        virtual
        nonReentrant
        onlyTurbineOwner
        whenNotPaused
        checkPermissions(_turbineId)
    {
        _burn(_turbineId);
    }

    function getBurnedFromServiceFees() external view returns (uint256) {
        return burnedFromRenaming + burnedFromMerging;
    }

    function liquidityReward(uint256 amountToReward) private {
        (, uint256 liquidityFee) = getPercentageOf(
            amountToReward,
            5 // Mint the 5% Treasury fee
        );
        wind.liquidityReward(liquidityFee);
    }

    // Mandatory overrides

    function _burn(uint256 tokenId)
        internal
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
    {
        TurbineEntity storage turbine = _turbines[tokenId];
        turbine.exists = false;
        logTier(turbine.rewardMult, -int256(turbine.turbineValue));
        ERC721Upgradeable._burn(tokenId);
        //ERC721URIStorageUpgradeable._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}