// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// todo implement IYieldSource interface
interface IYieldSource {

    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @notice Returns the reserve data for a given underlying asset
     * @param asset The address of the underlying asset
     */
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );
}

interface IAToken {
    /**
     * @notice Returns the balance of the user in the underlying asset
     * @param user The address of the user
     * @return The balance of the user
     */
    function balanceOf(address user) external view returns (uint256);
}

/**
 * @title YieldDonating Strategy Template
 * @author Octant
 * @notice Template for creating YieldDonating strategies that mint profits to donationAddress
 * @dev This strategy template works with the TokenizedStrategy pattern where
 *      initialization and management functions are handled by a separate contract.
 *      The strategy focuses on the core yield generation logic.
 *
 *      NOTE: To implement permissioned functions you can use the onlyManagement,
 *      onlyEmergencyAuthorized and onlyKeepers modifiers
 */
contract YieldDonatingStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    /// @notice Address of the yield source (e.g., Aave pool, Compound, Yearn vault)
    IYieldSource public immutable yieldSource;

    /// @notice Address of the aToken (interest-bearing token from the yield source)
    IAToken public immutable aToken;

    /**
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yieldSource,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        yieldSource = IYieldSource(_yieldSource);

        // Try to get the aToken address from the yield source (for Aave-like protocols)
        // This will fail silently if the yield source doesn't implement getReserveData
        try IYieldSource(_yieldSource).getReserveData(_asset) returns (
            uint256, uint128, uint128, uint128, uint128, uint128, uint40, uint16,
            address aTokenAddress,
            address, address, address, uint128, uint128, uint128
        ) {
            if (aTokenAddress != address(0)) {
                aToken = IAToken(aTokenAddress);
            }
        } catch {
            // If getReserveData fails, aToken will remain at address(0)
            // This allows the strategy to work with non-Aave yield sources
        }

        // max allow Yield source to withdraw assets
        ERC20(_asset).forceApprove(_yieldSource, type(uint256).max);

        // TokenizedStrategy initialization will be handled separately
        // This is just a template - the actual initialization depends on
        // the specific TokenizedStrategy implementation being used
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deploy.
     */
    function _deployFunds(uint256 _amount) internal override {
        // TODO: implement your logic to deploy funds into yield source
        // Example for AAVE:
        // yieldSource.supply(address(asset), _amount, address(this), 0);
        // Example for ERC4626 vault:
        // IERC4626(compounderVault).deposit(_amount, address(this));
        yieldSource.supply(address(asset), _amount, address(this), 0);
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // TODO: implement your logic to free funds from yield source
        // Example for AAVE:
        // yieldSource.withdraw(address(asset), _amount, address(this));
        // Example for ERC4626 vault:
        // uint256 shares = IERC4626(compounderVault).convertToShares(_amount);
        // IERC4626(compounderVault).redeem(shares, address(this), address(this));
        yieldSource.withdraw(address(asset), _amount, address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Only deploy funds if not in shutdown mode
        if (!TokenizedStrategy.isShutdown()) {
            // Deploy any loose/idle funds to the yield source
            uint256 looseAsset = asset.balanceOf(address(this));
            if (looseAsset > 0) {
                yieldSource.supply(address(asset), looseAsset, address(this), 0);
            }
        }

        // Calculate total assets
        uint256 deployedAssets;

        if (address(aToken) != address(0)) {
            // For Aave-like protocols: aToken balance represents underlying + accrued interest
            deployedAssets = aToken.balanceOf(address(this));
        } else {
            // For other yield sources: this should be overridden by the strategist
            // Default: assume no assets are deployed (all idle)
            deployedAssets = 0;
        }

        // Total assets = deployed in yield source + idle in strategy
        _totalAssets = deployedAssets + asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Can be overridden to implement withdrawal limits.
     * @return . The available amount that can be withdrawn.
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Can be overridden to implement deposit limits.
     * @param . The address that will deposit.
     * @return . The available amount that can be deposited.
     */
    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal virtual override {}

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        return false;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {}
}
