// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(
                    out,
                    and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF)
                )
                out := shl(8, out)
                out := add(
                    out,
                    and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF)
                )
                out := shl(8, out)
                out := add(
                    out,
                    and(mload(add(tablePtr, and(input, 0x3F))), 0xFF)
                )
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }

    function decode(bytes memory data) internal pure returns (bytes memory) {
        uint8[128] memory toInt;

        for (uint8 i = 0; i < bytes(TABLE).length; i++) {
            toInt[uint8(bytes(TABLE)[i])] = i;
        }

        uint256 delta;
        uint256 len = data.length;
        if (data[len - 2] == "=" && data[len - 1] == "=") {
            delta = 2;
        } else if (data[len - 1] == "=") {
            delta = 1;
        } else {
            delta = 0;
        }
        uint256 decodedLen = (len * 3) / 4 - delta;
        bytes memory buffer = new bytes(decodedLen);
        uint256 index;
        uint8 mask = 0xFF;

        for (uint256 i = 0; i < len; i += 4) {
            uint8 c0 = toInt[uint8(data[i])];
            uint8 c1 = toInt[uint8(data[i + 1])];
            buffer[index++] = (bytes1)(((c0 << 2) | (c1 >> 4)) & mask);
            if (index >= buffer.length) {
                return buffer;
            }
            uint8 c2 = toInt[uint8(data[i + 2])];
            buffer[index++] = (bytes1)(((c1 << 4) | (c2 >> 2)) & mask);
            if (index >= buffer.length) {
                return buffer;
            }
            uint8 c3 = toInt[uint8(data[i + 3])];
            buffer[index++] = (bytes1)(((c2 << 6) | c3) & mask);
        }
        return buffer;
    }
}
