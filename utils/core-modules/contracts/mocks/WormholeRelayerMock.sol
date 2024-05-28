//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {IWormhole} from "../interfaces/IWormhole.sol";
import {IWormholeReceiver} from "../interfaces/IWormholeReceiver.sol";

contract WormholeRelayerMock {
    event SendEvent(
        uint64 indexed sequence,
        uint256 deliveryQuote,
        uint256 paymentForExtraReceiverValue
    );

    event Delivery(
        address indexed recipientContract,
        uint16 indexed sourceChain,
        uint64 indexed sequence,
        bytes32 deliveryVaaHash,
        uint8 status,
        uint256 gasUsed,
        uint8 refundStatus,
        bytes additionalStatusInfo,
        bytes overridesInfo
    );

    IWormhole private immutable wormhole;

    constructor(address _wormhole) {
        wormhole = IWormhole(_wormhole);
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence) {
        bytes memory _payload = abi.encode(
            targetChain,
            targetAddress,
            payload,
            receiverValue,
            gasLimit
        );
        sequence = wormhole.publishMessage{value: 0}(0, _payload, 1);
        emit SendEvent(sequence, 0, 0);
    }

    function deliver(
        bytes[] memory encodedVMs,
        bytes memory encodedDeliveryVAA,
        address payable relayerRefundAddress,
        bytes memory deliveryOverrides
    ) public payable {
        // Parse and verify VAA containing delivery instructions, revert if invalid
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(
            encodedDeliveryVAA
        );

        (
            uint16 targetChain,
            address targetAddress,
            bytes memory payload,
            uint256 receiverValue,
            uint256 gasLimit
        ) = abi.decode(vm.payload, (uint16, address, bytes, uint256, uint256));

        IWormholeReceiver targetReceiver = IWormholeReceiver(targetAddress);

        require(targetChain == block.chainid, "Invalid target chain");

        targetReceiver.receiveEncodedMsg{value: receiverValue}(
            payload,
            new bytes[](0),
            vm.emitterAddress,
            vm.emitterChainId,
            vm.hash
        );

        emit Delivery(
            targetAddress,
            vm.emitterChainId,
            vm.sequence,
            vm.hash,
            1,
            0,
            6,
            bytes(""),
            bytes("")
        );
    }
}
