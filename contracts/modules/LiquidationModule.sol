//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Account} from "@synthetixio/main/contracts/storage/Account.sol";
import {ITokenModule} from "@synthetixio/core-modules/contracts/interfaces/ITokenModule.sol";
import {SafeCastI256, SafeCastU256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import {ILiquidationModule} from "../interfaces/ILiquidationModule.sol";
import {IPerpRewardDistributor} from "../interfaces/IPerpRewardDistributor.sol";
import {Margin} from "../storage/Margin.sol";
import {Order} from "../storage/Order.sol";
import {PerpMarket} from "../storage/PerpMarket.sol";
import {PerpMarketConfiguration, SYNTHETIX_USD_MARKET_ID} from "../storage/PerpMarketConfiguration.sol";
import {Position} from "../storage/Position.sol";
import {ErrorUtil} from "../utils/ErrorUtil.sol";
import {MathUtil} from "../utils/MathUtil.sol";
import {FeatureFlag} from "@synthetixio/core-modules/contracts/storage/FeatureFlag.sol";
import {Flags} from "../utils/Flags.sol";

contract LiquidationModule is ILiquidationModule {
    using DecimalMath for uint256;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using PerpMarket for PerpMarket.Data;
    using Position for Position.Data;

    // --- Runtime structs --- //

    struct Runtime_updateMarketPostFlag {
        uint256 availableSusd;
        uint256 supportedSynthMarketIdsLength;
        uint128 synthMarketId;
        uint256 availableAccountCollateral;
        uint128 poolId;
        uint256 poolCollateralTypesLength;
    }

    // --- Helpers --- //

    /**
     * @dev Before liquidation (not flag) to perform pre-steps and validation.
     */
    function updateMarketPreLiquidation(
        uint128 accountId,
        uint128 marketId,
        PerpMarket.Data storage market,
        uint256 oraclePrice,
        PerpMarketConfiguration.GlobalData storage globalConfig
    ) private returns (Position.Data storage oldPosition, Position.Data memory newPosition, uint256 liqKeeperFee) {
        (int256 fundingRate, ) = market.recomputeFunding(oraclePrice);
        emit FundingRecomputed(marketId, market.skew, fundingRate, market.getCurrentFundingVelocity());
        (uint256 utilizationRate, ) = market.recomputeUtilization(oraclePrice);
        emit UtilizationRecomputed(marketId, market.skew, utilizationRate);

        uint128 liqSize;

        (oldPosition, newPosition, liqSize, liqKeeperFee) = Position.validateLiquidation(
            accountId,
            market,
            PerpMarketConfiguration.load(marketId),
            globalConfig
        );

        // Track the liqSize that is about to be liquidated.
        market.updateAccumulatedLiquidation(liqSize);

        // Update market to reflect state of liquidated position.
        market.skew = market.skew - oldPosition.size + newPosition.size;
        market.size -= liqSize;

        // Update market debt relative to the keeperFee incurred.
        market.updateDebtCorrection(market.positions[accountId], newPosition);
    }

    /**
     * @dev Invoked post flag when position is dead and set to liquidate.
     */
    function updateMarketPostFlag(
        uint128 accountId,
        uint128 marketId,
        PerpMarket.Data storage market,
        PerpMarketConfiguration.GlobalData storage globalConfig
    ) private {
        Runtime_updateMarketPostFlag memory runtime;

        Margin.Data storage accountMargin = Margin.load(accountId, marketId);
        runtime.availableSusd = accountMargin.collaterals[SYNTHETIX_USD_MARKET_ID];

        // Clear out sUSD associated with the account of the liquidated position.
        if (runtime.availableSusd > 0) {
            market.depositedCollateral[SYNTHETIX_USD_MARKET_ID] -= runtime.availableSusd;
            accountMargin.collaterals[SYNTHETIX_USD_MARKET_ID] = 0;
        }

        // For non-sUSD collateral, send to their respective reward distributor, create new distriction per collateral,
        // and then wipe out all associated collateral on the account.
        Margin.GlobalData storage globalMarginConfig = Margin.load();
        runtime.supportedSynthMarketIdsLength = globalMarginConfig.supportedSynthMarketIds.length;

        // Iterate over all supported margin collateral types to see if any should be distributed to LPs.
        for (uint256 i = 0; i < runtime.supportedSynthMarketIdsLength; ) {
            runtime.synthMarketId = globalMarginConfig.supportedSynthMarketIds[i];
            runtime.availableAccountCollateral = accountMargin.collaterals[runtime.synthMarketId];

            // Found a deposited collateral that must be distributed.
            if (runtime.availableAccountCollateral > 0) {
                address synth = globalConfig.spotMarket.getSynth(runtime.synthMarketId);
                globalConfig.synthetix.withdrawMarketCollateral(marketId, synth, runtime.availableAccountCollateral);
                IPerpRewardDistributor distributor = IPerpRewardDistributor(
                    globalMarginConfig.supported[runtime.synthMarketId].rewardDistributor
                );
                ITokenModule(synth).transfer(address(distributor), runtime.availableAccountCollateral);

                runtime.poolId = distributor.getPoolId();
                address[] memory poolCollateralTypes = distributor.getCollateralTypes();
                runtime.poolCollateralTypesLength = poolCollateralTypes.length;

                // Calculate the USD value of each collateral delegated to pool.
                uint256[] memory collateralValuesUsd = new uint256[](runtime.poolCollateralTypesLength);
                uint256 totalCollateralValueUsd;
                for (uint256 j = 0; j < runtime.poolCollateralTypesLength; ) {
                    (, uint256 collateralValueUsd) = globalConfig.synthetix.getVaultCollateral(
                        runtime.poolId,
                        poolCollateralTypes[j]
                    );
                    totalCollateralValueUsd += collateralValueUsd;
                    collateralValuesUsd[j] = collateralValueUsd;

                    unchecked {
                        ++j;
                    }
                }

                // Infer the ratio of size to distribute, proportional to value of each delegated collateral.
                uint256 remainingAmountToDistribute = runtime.availableAccountCollateral;
                for (uint256 k = 0; k < runtime.poolCollateralTypesLength; ) {
                    // Ensure total amounts fully distributed, the last collateral receives the remainder.
                    if (k == runtime.poolCollateralTypesLength - 1) {
                        distributor.distributeRewards(poolCollateralTypes[k], remainingAmountToDistribute);
                    } else {
                        uint256 amountToDistribute = runtime.availableAccountCollateral.mulDecimal(
                            collateralValuesUsd[k].divDecimal(totalCollateralValueUsd)
                        );
                        remainingAmountToDistribute -= amountToDistribute;
                        distributor.distributeRewards(poolCollateralTypes[k], amountToDistribute);
                    }

                    unchecked {
                        ++k;
                    }
                }

                // Clear out non-sUSD collateral associated with the account of the liquidated position.
                market.depositedCollateral[runtime.synthMarketId] -= runtime.availableAccountCollateral;
                accountMargin.collaterals[runtime.synthMarketId] = 0;
            }

            unchecked {
                ++i;
            }
        }
    }

    // --- Mutative --- //

    /**
     * @inheritdoc ILiquidationModule
     */
    function flagPosition(uint128 accountId, uint128 marketId) external {
        FeatureFlag.ensureAccessToFeature(Flags.FLAG_POSITION);
        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        Position.Data storage position = market.positions[accountId];

        // Cannot flag a position that does not exist.
        if (position.size == 0) {
            revert ErrorUtil.PositionNotFound();
        }

        // Cannot flag for liquidation unless they are liquidatable.
        uint256 oraclePrice = market.getOraclePrice();
        bool isLiquidatable = position.isLiquidatable(
            market,
            Margin.getMarginUsd(accountId, market, oraclePrice, true /* useHaircutCollateralPrice */),
            oraclePrice,
            PerpMarketConfiguration.load(marketId)
        );
        if (!isLiquidatable) {
            revert ErrorUtil.CannotLiquidatePosition();
        }

        // Cannot reflag something that's already flagged.
        if (market.flaggedLiquidations[accountId] != address(0)) {
            revert ErrorUtil.PositionFlagged();
        }

        // Remove any pending orders that may exist.
        Order.Data storage order = market.orders[accountId];
        if (order.sizeDelta != 0) {
            emit OrderCanceled(accountId, marketId, 0, order.commitmentTime);
            delete market.orders[accountId];
        }
        PerpMarketConfiguration.GlobalData storage globalConfig = PerpMarketConfiguration.load();

        uint256 flagReward = Position.getLiquidationFlagReward(
            MathUtil.abs(position.size).to128(),
            oraclePrice,
            PerpMarketConfiguration.load(marketId),
            globalConfig
        );

        Position.Data memory newPosition = Position.Data(
            position.size,
            position.entryFundingAccrued,
            position.entryUtilizationAccrued,
            position.entryPrice,
            position.accruedFeesUsd + flagReward
        );
        market.updateDebtCorrection(position, newPosition);

        // Update position and market accounting.
        position.update(newPosition);
        updateMarketPostFlag(accountId, marketId, market, globalConfig);

        // Flag and emit event.
        market.flaggedLiquidations[accountId] = msg.sender;

        // Pay flagger.
        globalConfig.synthetix.withdrawMarketUsd(marketId, msg.sender, flagReward);

        emit PositionFlaggedLiquidation(accountId, marketId, msg.sender, flagReward, oraclePrice);
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function liquidatePosition(uint128 accountId, uint128 marketId) external {
        FeatureFlag.ensureAccessToFeature(Flags.LIQUIDATE_POSITION);

        Account.exists(accountId);
        PerpMarket.Data storage market = PerpMarket.exists(marketId);

        // Cannot liquidate a position that does not exist.
        if (market.positions[accountId].size == 0) {
            revert ErrorUtil.PositionNotFound();
        }

        uint256 oraclePrice = market.getOraclePrice();
        PerpMarketConfiguration.GlobalData storage globalConfig = PerpMarketConfiguration.load();

        address flagger = market.flaggedLiquidations[accountId];
        (, Position.Data memory newPosition, uint256 liqKeeperFee) = updateMarketPreLiquidation(
            accountId,
            marketId,
            market,
            oraclePrice,
            globalConfig
        );

        if (newPosition.size == 0) {
            delete market.positions[accountId];
            delete market.flaggedLiquidations[accountId];
        } else {
            market.positions[accountId].update(newPosition);
        }

        // Pay the keeper
        globalConfig.synthetix.withdrawMarketUsd(marketId, msg.sender, liqKeeperFee);

        emit PositionLiquidated(accountId, marketId, newPosition.size, msg.sender, flagger, liqKeeperFee, oraclePrice);
    }

    // --- Views --- //

    /**
     * @inheritdoc ILiquidationModule
     */
    function getLiquidationFees(
        uint128 accountId,
        uint128 marketId
    ) external view returns (uint256 flagKeeperReward, uint256 liqKeeperFee) {
        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        PerpMarketConfiguration.GlobalData storage globalConfig = PerpMarketConfiguration.load();
        PerpMarketConfiguration.Data storage marketConfig = PerpMarketConfiguration.load(marketId);
        uint128 absSize = MathUtil.abs(market.positions[accountId].size).to128();

        // Return empty when a position does not exist.
        if (absSize == 0) {
            return (0, 0);
        }

        flagKeeperReward = Position.getLiquidationFlagReward(
            absSize,
            market.getOraclePrice(),
            marketConfig,
            globalConfig
        );
        liqKeeperFee = Position.getLiquidationKeeperFee(absSize, marketConfig, globalConfig);
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function getRemainingLiquidatableSizeCapacity(
        uint128 marketId
    )
        external
        view
        returns (uint128 maxLiquidatableCapacity, uint128 remainingCapacity, uint128 lastLiquidationTimestamp)
    {
        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        return market.getRemainingLiquidatableSizeCapacity(PerpMarketConfiguration.load(marketId));
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function isPositionLiquidatable(uint128 accountId, uint128 marketId) external view returns (bool) {
        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        uint256 oraclePrice = market.getOraclePrice();
        return
            market.positions[accountId].isLiquidatable(
                market,
                Margin.getMarginUsd(accountId, market, oraclePrice, true /* useHaircutCollateralPrice */),
                oraclePrice,
                PerpMarketConfiguration.load(marketId)
            );
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function getLiquidationMarginUsd(
        uint128 accountId,
        uint128 marketId
    ) external view returns (uint256 im, uint256 mm) {
        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        PerpMarketConfiguration.Data storage marketConfig = PerpMarketConfiguration.load(marketId);
        (im, mm, ) = Position.getLiquidationMarginUsd(
            market.positions[accountId].size,
            market.getOraclePrice(),
            marketConfig
        );
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function getHealthFactor(uint128 accountId, uint128 marketId) external view returns (uint256) {
        Account.exists(accountId);

        PerpMarket.Data storage market = PerpMarket.exists(marketId);
        Position.Data storage position = market.positions[accountId];

        uint256 oraclePrice = market.getOraclePrice();
        Position.HealthData memory healthData = Position.getHealthData(
            market,
            position.size,
            position.entryPrice,
            position.entryFundingAccrued,
            position.entryUtilizationAccrued,
            Margin.getMarginUsd(accountId, market, oraclePrice, true /* useHaircutCollateralPrice */),
            oraclePrice,
            PerpMarketConfiguration.load(marketId)
        );
        return healthData.healthFactor;
    }
}
