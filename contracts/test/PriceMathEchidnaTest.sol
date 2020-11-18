// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.6.12;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/PriceMath.sol';
import '../libraries/TickMath.sol';

contract PriceMathEchidnaTest {
    using SafeMath for uint256;

    function getAmountOutInvariants(
        uint112 reserveIn,
        uint112 reserveOut,
        uint112 amountIn
    ) external pure {
        require(reserveIn > 0 && reserveOut > 0);

        uint112 amountOut = PriceMath.getAmountOut(reserveIn, reserveOut, amountIn);
        assert(amountOut < reserveOut);

        uint256 k = uint256(reserveIn).mul(reserveOut);
        uint256 reserveInAfter = uint256(reserveIn).add(amountIn);
        uint256 reserveOutAfter = uint256(reserveOut).sub(amountOut);
        uint256 kAfter = reserveInAfter.mul(reserveOutAfter);
        assert(kAfter >= k);
    }

    function roundingCanBeGreaterThan1(uint224 price, uint256 liquidity) external pure {
        require(price >= TickMath.getRatioAtTick(TickMath.MIN_TICK)._x);
        require(price <= TickMath.getRatioAtTick(TickMath.MAX_TICK)._x);

        (uint112 amount0Up, uint112 amount1Up) = PriceMath.getVirtualReservesAtPrice(
            FixedPoint.uq112x112(price),
            liquidity,
            true
        );
        (uint112 amount0Down, uint112 amount1Down) = PriceMath.getVirtualReservesAtPrice(
            FixedPoint.uq112x112(price),
            liquidity,
            false
        );
        assert(amount0Up >= amount0Down);
        assert(amount1Up >= amount1Down);
        assert(amount0Up - amount0Down <= 2);
        assert(amount1Up - amount1Down <= 2);
    }

    function getInputToRatioInvariants(
        uint224 priceRaw,
        int16 tickTarget,
        uint112 liquidity,
        uint16 lpFee
    ) external pure {
        require(tickTarget >= TickMath.MIN_TICK && tickTarget < TickMath.MAX_TICK);
        require(liquidity > 0);
        require(lpFee > 0 && lpFee < PriceMath.LP_FEE_BASE);

        FixedPoint.uq112x112 memory price = FixedPoint.uq112x112(priceRaw);
        (uint112 reserve0, uint112 reserve1) = PriceMath.getVirtualReservesAtPrice(price, liquidity, false);

        require(reserve0 > 0 && reserve1 > 0);

        FixedPoint.uq112x112 memory priceTarget = TickMath.getRatioAtTick(tickTarget);
        bool zeroForOne = price._x >= priceTarget._x;

        (uint112 amountIn, uint112 amountOutMax) = PriceMath.getInputToRatio(
            reserve0,
            reserve1,
            liquidity,
            priceTarget,
            lpFee,
            zeroForOne
        );

        if (amountIn == 0) {
            // amountIn should only be 0 if the current price is past the target price
            if (zeroForOne) assert(price._x <= priceTarget._x);
            else assert(price._x >= priceTarget._x);
            assert(amountOutMax == 0);
        } else {
            assert((zeroForOne ? reserve1 : reserve0) > amountOutMax);

            uint112 amountInLessFee = uint112(
                (uint256(amountIn) * (PriceMath.LP_FEE_BASE - lpFee)) / PriceMath.LP_FEE_BASE
            );
            uint112 amountOut = zeroForOne
                ? PriceMath.getAmountOut(reserve0, reserve1, amountInLessFee)
                : PriceMath.getAmountOut(reserve1, reserve0, amountInLessFee);

            // downward-adjust amount out if necessary
            amountOut = uint112(Math.min(amountOut, amountOutMax));

            // (uint112 reserve0Next, uint112 reserve1Next) = zeroForOne
            //     ? (reserve0 + amountInLessFee, reserve1 - amountOut)
            //     : (reserve0 - amountOut, reserve1 + amountInLessFee);

            // // check that the price does not exceed the next price
            // {
            //     FixedPoint.uq112x112 memory priceAfterSwap = FixedPoint.fraction(reserve1Next, reserve0Next);
            //     if (zeroForOne) assert(priceAfterSwap._x >= priceTarget._x);
            //     else assert(priceAfterSwap._x <= priceTarget._x);
            // }

            // (reserve0Next, reserve1Next) = zeroForOne
            //     ? (reserve0 + amountInLessFee + 1, reserve1 - amountOut)
            //     : (reserve0 - amountOut, reserve1 + amountInLessFee + 1);

            // // check that one more wei of amount in would result in a price that exceeds the next price
            // {
            //     FixedPoint.uq112x112 memory priceAfterSwap1MoreWei = FixedPoint.fraction(reserve1Next, reserve0Next);
            //     if (zeroForOne) assert(priceAfterSwap1MoreWei._x <= priceTarget._x);
            //     else assert(priceAfterSwap1MoreWei._x >= priceTarget._x);
            // }
        }
    }
}