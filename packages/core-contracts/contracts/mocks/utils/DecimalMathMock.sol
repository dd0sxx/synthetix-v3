//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../utils/DecimalMath.sol";

contract DecimalMathMock {
    // -----------------
    // uint256
    // -----------------

    function mulDecimal(uint256 x, uint256 y) public pure returns (uint256) {
        return DecimalMath.mulDecimal(x, y);
    }

    function divDecimal(uint256 x, uint256 y) public pure returns (uint256) {
        return DecimalMath.divDecimal(x, y);
    }

    // -----------------
    // uint128
    // -----------------

    function mulDecimalUint128(uint128 x, uint128 y) public pure returns (uint128) {
        return DecimalMath.mulDecimalUint128(x, y);
    }

    function divDecimalUint128(uint128 x, uint128 y) public pure returns (uint128) {
        return DecimalMath.divDecimalUint128(x, y);
    }

    // -----------------
    // int256
    // -----------------

    function mulDecimal(int256 x, int256 y) public pure returns (int256) {
        return DecimalMath.mulDecimal(x, y);
    }

    function divDecimal(int256 x, int256 y) public pure returns (int256) {
        return DecimalMath.divDecimal(x, y);
    }

    // -----------------
    // int128
    // -----------------

    function mulDecimalInt128(int128 x, int128 y) public pure returns (int128) {
        return DecimalMath.mulDecimalInt128(x, y);
    }

    function divDecimalInt128(int128 x, int128 y) public pure returns (int128) {
        return DecimalMath.divDecimalInt128(x, y);
    }
}