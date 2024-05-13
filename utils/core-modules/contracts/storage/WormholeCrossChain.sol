//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IWormhole} from "./../interfaces/IWormhole.sol";

import {AccessError} from "@synthetixio/core-contracts/contracts/errors/AccessError.sol";
import {OwnableStorage} from "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import {ParameterError} from "@synthetixio/core-contracts/contracts/errors/ParameterError.sol";
import {SetUtil} from "@synthetixio/core-contracts/contracts/utils/SetUtil.sol";
import "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
/**
 * @title System wide configuration for anything related to cross-chain
 */
library WormholeCrossChain {
    using SetUtil for SetUtil.UintSet;
    using SafeCastU256 for uint256;

    bytes32 private constant _SLOT_WORMHOLE_CROSS_CHAIN =
        keccak256(abi.encode("io.synthetix.core-modules.WormholeCrossChain"));

    struct Data {
        IWormhole wormhole;
        uint32 nonce;
        mapping(uint16 => bytes32) registeredEmitters; //chain id => emitter address
        mapping(bytes32 => bool) hasProcessedMessage;
    }

    function configureWormhole(
        IWormhole wormhole,
        uint16[] memory supportedNetworks,
        bytes32[] memory emitters
    ) external {
        OwnableStorage.onlyOwner();

        if (supportedNetworks.length != emitters.length) {
            revert ParameterError.InvalidParameter(
                "emitters",
                "must match length of supportedNetworks"
            );
        }

        Data storage wh = load();
        wh.wormhole = wormhole;

        for (uint256 i = 0; i < supportedNetworks.length; i++) {
            wh.registeredEmitters[supportedNetworks[i]] = emitters[i];
        }
    }

    function load() internal pure returns (Data storage crossChain) {
        bytes32 s = _SLOT_WORMHOLE_CROSS_CHAIN;
        assembly {
            crossChain.slot := s
        }
    }

    function onlyCrossChain() internal view {
        if (ERC2771Context._msgSender() != address(this)) {
            revert AccessError.Unauthorized(ERC2771Context._msgSender());
        }
    }

    function emitterAddress() public view returns (bytes32) {
        return bytes32(uint256(uint160(address(this))));
    }
}
