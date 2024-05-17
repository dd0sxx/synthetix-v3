//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {IWormhole} from "./../interfaces/IWormhole.sol";
import {IWormholeRelayer} from "./../interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "./../interfaces/IWormholeReceiver.sol";
import "../storage/WormholeCrossChain.sol";
// import "wormhole-solidity-sdk/interfaces/IWormholeRelayerRelayer.sol";
// import "wormhole-solidity-sdk/interfaces/IWormholeRelayerReceiver.sol";

/**
 * @title Module with assorted cross-chain functions.
 */
contract WormholeCrossChainModule is IWormholeReceiver {
    function registerEmitter(uint16 chainId, bytes32 emitterAddress) public {
        // require(msg.sender == owner);
        WormholeCrossChain.Data storage wh = WormholeCrossChain.load();
        wh.registeredEmitters[chainId] = emitterAddress;
    }

    function receiveEncodedMsg(
        bytes memory encodedMsg,
        bytes[] memory additionalVaas,
        bytes32 sender,
        uint16 sourceChain,
        bytes32 deliveryId
    ) public payable override {
        WormholeCrossChain.Data storage wh = WormholeCrossChain.load();
        // require(msg.sender == address(wh.wormholeRelayer), "Only relayer allowed");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wh
            .wormholeCore
            .parseAndVerifyVM(encodedMsg);

        //1. Check Wormhole Guardian Signatures
        //  If the VM is NOT valid, will return the reason it's not valid
        //  If the VM IS valid, reason will be blank
        require(valid, reason);

        //2. Check if the Emitter Chain contract is registered
        require(
            wh.registeredEmitters[vm.emitterChainId] == vm.emitterAddress,
            "Invalid Emitter Address!"
        );

        //3. Check that the message hasn't already been processed
        require(!wh.hasProcessedMessage[vm.hash], "Message already processed");
        wh.hasProcessedMessage[vm.hash] = true;

        // do the thing!
        (bool success, bytes memory result) = address(this).call(vm.payload);
        require(success, "Failed to execute payload");
    }

    function transmit(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) public returns (uint64 sequence) {
        WormholeCrossChain.Data storage wh = WormholeCrossChain.load();
        sequence = wh.wormholeRelayer.sendPayloadToEvm(
            targetChain,
            targetAddress,
            payload,
            receiverValue,
            gasLimit
        );
    }

    /**
     * @notice Returns the cost (in wei) of a greeting
     */
    function quoteCrossChainGreeting(
        uint16 targetChain,
        uint256 gasLimit
    ) public view returns (uint256 cost) {
        WormholeCrossChain.Data storage wh = WormholeCrossChain.load();
        // Cost of requesting a message to be sent to
        // chain 'targetChain' with a gasLimit of 'GAS_LIMIT'
        (cost, ) = wh.wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, gasLimit);
    }

    function toAddress(bytes32 _bytes) internal pure returns (address) {
        address addr;
        assembly {
            addr := mload(add(_bytes, 20))
        }
        return addr;
    }
}
