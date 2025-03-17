// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable not-rely-on-time

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { LogExpMath } from "@balancer-labs/v3-solidity-utils/contracts/math/LogExpMath.sol";

struct SqrtQ0State {
    uint256 startSqrtQ0;
    uint256 endSqrtQ0;
    uint256 startTime;
    uint256 endTime;
}

library AclAmmMath {
    using FixedPoint for uint256;

    function computeInvariant(
        uint256[] memory balancesScaled18,
        uint256[] memory lastVirtualBalances,
        uint256 c,
        uint256 lastTimestamp,
        uint256 centerednessMargin,
        SqrtQ0State memory sqrtQ0State,
        Rounding rounding
    ) internal view returns (uint256) {
        (uint256[] memory virtualBalances, ) = getVirtualBalances(
            balancesScaled18,
            lastVirtualBalances,
            c,
            lastTimestamp,
            block.timestamp,
            centerednessMargin,
            sqrtQ0State
        );

        return computeInvariant(balancesScaled18, virtualBalances, rounding);
    }

    function computeInvariant(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        Rounding rounding
    ) internal pure returns (uint256) {
        function(uint256, uint256) pure returns (uint256) _mulUpOrDown = rounding == Rounding.ROUND_DOWN
            ? FixedPoint.mulDown
            : FixedPoint.mulUp;

        return _mulUpOrDown((balancesScaled18[0] + virtualBalances[0]), (balancesScaled18[1] + virtualBalances[1]));
    }

    function calculateOutGivenIn(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountGivenScaled18
    ) internal pure returns (uint256) {
        uint256[] memory finalBalances = new uint256[](balancesScaled18.length);

        finalBalances[0] = balancesScaled18[0] + virtualBalances[0];
        finalBalances[1] = balancesScaled18[1] + virtualBalances[1];

        uint256 invariant = finalBalances[0].mulDown(finalBalances[1]);

        return finalBalances[tokenOutIndex] - invariant.divDown(finalBalances[tokenInIndex] + amountGivenScaled18);
    }

    function calculateInGivenOut(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountGivenScaled18
    ) internal pure returns (uint256) {
        uint256[] memory finalBalances = new uint256[](balancesScaled18.length);

        finalBalances[0] = balancesScaled18[0] + virtualBalances[0];
        finalBalances[1] = balancesScaled18[1] + virtualBalances[1];

        uint256 invariant = finalBalances[0].mulUp(finalBalances[1]);

        return invariant.divUp(finalBalances[tokenOutIndex] - amountGivenScaled18) - finalBalances[tokenInIndex];
    }

    function initializeVirtualBalances(
        uint256[] memory balancesScaled18,
        uint256 sqrtQ0
    ) internal pure returns (uint256[] memory virtualBalances) {
        virtualBalances = new uint256[](balancesScaled18.length);
        virtualBalances[0] = balancesScaled18[0].divDown(sqrtQ0 - FixedPoint.ONE);
        virtualBalances[1] = balancesScaled18[1].divDown(sqrtQ0 - FixedPoint.ONE);
    }

    function getVirtualBalances(
        uint256[] memory balancesScaled18,
        uint256[] memory lastVirtualBalances,
        uint256 c,
        uint256 lastTimestamp,
        uint256 currentTimestamp,
        uint256 centerednessMargin,
        SqrtQ0State memory sqrtQ0State //TODO: optimize gas usage
    ) internal view returns (uint256[] memory virtualBalances, bool changed) {
        // TODO Review rounding
        // TODO: try to find better way to change the virtual balances in storage

        virtualBalances = lastVirtualBalances;

        // Calculate currentSqrtQ0
        uint256 currentSqrtQ0 = calculateSqrtQ0(
            currentTimestamp,
            sqrtQ0State.startSqrtQ0,
            sqrtQ0State.endSqrtQ0,
            sqrtQ0State.startTime,
            sqrtQ0State.endTime
        );

        if (isPoolInRange(balancesScaled18, lastVirtualBalances, centerednessMargin) == false) {
            uint256 q0 = currentSqrtQ0.mulDown(currentSqrtQ0);

            if (isAboveCenter(balancesScaled18, lastVirtualBalances)) {
                virtualBalances[1] = lastVirtualBalances[1].mulDown(
                    LogExpMath.pow(FixedPoint.ONE - c, (block.timestamp - lastTimestamp) * FixedPoint.ONE)
                );
                // Va = (Ra * (Vb + Rb)) / (((Q0 - 1) * Vb) - Rb)
                virtualBalances[0] = (balancesScaled18[0].mulDown(virtualBalances[1] + balancesScaled18[1])).divDown(
                    (q0 - FixedPoint.ONE).mulDown(virtualBalances[1]) - balancesScaled18[1]
                );
            } else {
                virtualBalances[0] = lastVirtualBalances[0].mulDown(
                    LogExpMath.pow(FixedPoint.ONE - c, (block.timestamp - lastTimestamp) * FixedPoint.ONE)
                );
                // Vb = (Rb * (Va + Ra)) / (((Q0 - 1) * Va) - Ra)
                virtualBalances[1] = (balancesScaled18[1].mulDown(virtualBalances[0] + balancesScaled18[0])).divDown(
                    (q0 - FixedPoint.ONE).mulDown(virtualBalances[0]) - balancesScaled18[0]
                );
            }

            changed = true;
        } else if (sqrtQ0State.startTime != 0 && currentTimestamp > sqrtQ0State.startTime) {
            uint256 lastSqrtQ0 = calculateSqrtQ0(
                lastTimestamp,
                sqrtQ0State.startSqrtQ0,
                sqrtQ0State.endSqrtQ0,
                sqrtQ0State.startTime,
                sqrtQ0State.endTime
            );

            // Ra_center = Va * (lastSqrtQ0 - 1)
            uint256 rACenter = lastVirtualBalances[0].mulDown(lastSqrtQ0 - FixedPoint.ONE);

            // Va = Ra_center / (currentSqrtQ0 - 1)
            virtualBalances[0] = rACenter.divDown(currentSqrtQ0 - FixedPoint.ONE);

            uint256 currentInvariant = computeInvariant(balancesScaled18, lastVirtualBalances, Rounding.ROUND_DOWN);

            // Vb = currentInvariant / (currentQ0 * Va)
            virtualBalances[1] = currentInvariant.divDown(
                currentSqrtQ0.mulDown(currentSqrtQ0).mulDown(virtualBalances[0])
            );

            changed = true;
        }
    }

    function isPoolInRange(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 centerednessMargin
    ) internal pure returns (bool) {
        uint256 centeredness = calculateCenteredness(balancesScaled18, virtualBalances);
        return centeredness >= centerednessMargin;
    }

    function calculateCenteredness(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances
    ) internal pure returns (uint256) {
        if (balancesScaled18[0] == 0 || balancesScaled18[1] == 0) {
            return 0;
        } else if (isAboveCenter(balancesScaled18, virtualBalances)) {
            return
                balancesScaled18[1].mulDown(virtualBalances[0]).divDown(
                    balancesScaled18[0].mulDown(virtualBalances[1])
                );
        } else {
            return
                balancesScaled18[0].mulDown(virtualBalances[1]).divDown(
                    balancesScaled18[1].mulDown(virtualBalances[0])
                );
        }
    }

    function calculateSqrtQ0(
        uint256 currentTime,
        uint256 startSqrtQ0,
        uint256 endSqrtQ0,
        uint256 startTime,
        uint256 endTime
    ) internal pure returns (uint256) {
        if (currentTime <= startTime) {
            return startSqrtQ0;
        } else if (currentTime >= endTime) {
            return endSqrtQ0;
        }

        uint256 exponent = ((currentTime - startTime) * FixedPoint.ONE).divDown((endTime - startTime) * FixedPoint.ONE);
        uint256 base = endSqrtQ0.divDown(startSqrtQ0);

        return startSqrtQ0.mulDown(base.powDown(exponent));
    }

    function isAboveCenter(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances
    ) internal pure returns (bool) {
        if (balancesScaled18[1] == 0) {
            return true;
        } else {
            return balancesScaled18[0].divDown(balancesScaled18[1]) > virtualBalances[0].divDown(virtualBalances[1]);
        }
    }

    function parseIncreaseDayRate(uint256 increaseDayRate) internal pure returns (uint256) {
        // Divide daily rate by a number of seconds per day (plus some adjustment) = 86400 + 25%
        return increaseDayRate / 110000;
    }
}
