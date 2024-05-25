//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./lib/TypedUnits.sol";

import {DeliveryProviderDoesNotSupportTargetChain, DeliveryProviderDoesNotSupportMessageKeyType, InvalidMsgValue, DeliveryProviderCannotReceivePayment, MessageKey, VaaKey, IWormholeRelayerSend, VAA_KEY_TYPE} from "./interfaces/IWormholeRelayerTyped.sol";
import {IWormhole} from "@synthetixio/core-modules/contracts/interfaces/IWormhole.sol";
import {IDeliveryProvider} from "@synthetixio/core-modules/contracts/interfaces/IDeliveryProvider.sol";

contract WormholeRelayerMock {
    using TargetNativeLib for TargetNative;

    struct Send {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes payload;
        TargetNative receiverValue;
        LocalNative paymentForExtraReceiverValue;
        bytes encodedExecutionParameters;
        uint16 refundChain;
        bytes32 refundAddress;
        address deliveryProviderAddress;
        MessageKey[] messageKeys;
        uint8 consistencyLevel;
    }

    struct EvmExecutionParamsV1 {
        Gas gasLimit;
    }

    enum ExecutionParamsVersion {
        EVM_V1
    }

    uint8 internal constant CONSISTENCY_LEVEL_FINALIZED = 15;
    uint8 internal constant CONSISTENCY_LEVEL_INSTANT = 200;

    IWormhole private immutable wormhole;
    IDeliveryProvider private immutable deliveryProvider;
    uint16 private immutable chainId;

    constructor(address _wormhole, address _deliveryProvider) {
        wormhole = IWormhole(_wormhole);
        deliveryProvider = IDeliveryProvider(_deliveryProvider);
        chainId = uint16(wormhole.chainId());
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        TargetNative receiverValue,
        Gas gasLimit
    ) external payable returns (uint64 sequence) {
        return
            sendToEvm(
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                LocalNative.wrap(0),
                gasLimit,
                targetChain,
                address(0x0),
                getDefaultDeliveryProvider(),
                new VaaKey[](0),
                CONSISTENCY_LEVEL_FINALIZED
            );
    }

    function sendToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        TargetNative receiverValue,
        LocalNative paymentForExtraReceiverValue,
        Gas gasLimit,
        uint16 refundChain,
        address refundAddress,
        address deliveryProviderAddress,
        VaaKey[] memory vaaKeys,
        uint8 consistencyLevel
    ) public payable returns (uint64 sequence) {
        sequence = send(
            targetChain,
            toWormholeFormat(targetAddress),
            payload,
            receiverValue,
            paymentForExtraReceiverValue,
            encodeEvmExecutionParamsV1(EvmExecutionParamsV1(gasLimit)),
            refundChain,
            toWormholeFormat(refundAddress),
            deliveryProviderAddress,
            vaaKeys,
            consistencyLevel
        );
    }

    function send(
        uint16 targetChain,
        bytes32 targetAddress,
        bytes memory payload,
        TargetNative receiverValue,
        LocalNative paymentForExtraReceiverValue,
        bytes memory encodedExecutionParameters,
        uint16 refundChain,
        bytes32 refundAddress,
        address deliveryProviderAddress,
        VaaKey[] memory vaaKeys,
        uint8 consistencyLevel
    ) public payable returns (uint64 sequence) {
        sequence = send(
            Send(
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                paymentForExtraReceiverValue,
                encodedExecutionParameters,
                refundChain,
                refundAddress,
                deliveryProviderAddress,
                vaaKeyArrayToMessageKeyArray(vaaKeys),
                consistencyLevel
            )
        );
    }

    function send(
        uint16 targetChain,
        bytes32 targetAddress,
        bytes memory payload,
        TargetNative receiverValue,
        LocalNative paymentForExtraReceiverValue,
        bytes memory encodedExecutionParameters,
        uint16 refundChain,
        bytes32 refundAddress,
        address deliveryProviderAddress,
        MessageKey[] memory messageKeys,
        uint8 consistencyLevel
    ) public payable returns (uint64 sequence) {
        sequence = send(
            Send(
                targetChain,
                targetAddress,
                payload,
                receiverValue,
                paymentForExtraReceiverValue,
                encodedExecutionParameters,
                refundChain,
                refundAddress,
                deliveryProviderAddress,
                messageKeys,
                consistencyLevel
            )
        );
    }

    function send(Send memory sendParams) internal returns (uint64 sequence) {
        IDeliveryProvider provider = IDeliveryProvider(sendParams.deliveryProviderAddress);

        // Revert if delivery provider does not support the target chain
        if (!provider.isChainSupported(sendParams.targetChain)) {
            revert DeliveryProviderDoesNotSupportTargetChain(
                sendParams.deliveryProviderAddress,
                sendParams.targetChain
            );
        }

        // Obtain the delivery provider's fee for this delivery, as well as some encoded info (e.g. refund per unit of gas unused)
        (LocalNative deliveryPrice, bytes memory encodedExecutionInfo) = provider
            .quoteDeliveryPrice(
                sendParams.targetChain,
                sendParams.receiverValue,
                sendParams.encodedExecutionParameters
            );

        // Check if user passed in 'one wormhole message fee' + 'delivery provider's fee'
        LocalNative wormholeMessageFee = getWormholeMessageFee();
        checkMsgValue(wormholeMessageFee, deliveryPrice, sendParams.paymentForExtraReceiverValue);

        checkKeyTypesSupported(provider, sendParams.messageKeys);

        // Encode all relevant info the delivery provider needs to perform the delivery as requested
        bytes memory encodedInstruction = DeliveryInstruction({
            targetChain: sendParams.targetChain,
            targetAddress: sendParams.targetAddress,
            payload: sendParams.payload,
            requestedReceiverValue: sendParams.receiverValue,
            extraReceiverValue: provider.quoteAssetConversion(
                sendParams.targetChain,
                sendParams.paymentForExtraReceiverValue
            ),
            encodedExecutionInfo: encodedExecutionInfo,
            refundChain: sendParams.refundChain,
            refundAddress: sendParams.refundAddress,
            refundDeliveryProvider: provider.getTargetChainAddress(sendParams.targetChain),
            sourceDeliveryProvider: toWormholeFormat(sendParams.deliveryProviderAddress),
            senderAddress: toWormholeFormat(msg.sender),
            messageKeys: sendParams.messageKeys
        }).encode();

        // Publish the encoded delivery instruction as a wormhole message
        // and pay the delivery provider their fee
        bool paymentSucceeded;
        (sequence, paymentSucceeded) = publishAndPay(
            wormholeMessageFee,
            deliveryPrice,
            sendParams.paymentForExtraReceiverValue,
            encodedInstruction,
            sendParams.consistencyLevel,
            provider.getRewardAddress()
        );

        if (!paymentSucceeded) {
            revert DeliveryProviderCannotReceivePayment();
        }
    }

    function vaaKeyArrayToMessageKeyArray(
        VaaKey[] memory vaaKeys
    ) internal pure returns (MessageKey[] memory msgKeys) {
        msgKeys = new MessageKey[](vaaKeys.length);
        uint256 len = vaaKeys.length;
        for (uint256 i = 0; i < len; ) {
            msgKeys[i] = MessageKey(VAA_KEY_TYPE, encodeVaaKey(vaaKeys[i]));
            unchecked {
                ++i;
            }
        }
    }

    function getDefaultDeliveryProvider() public view returns (address deliveryProvider) {
        return deliveryProvider;
    }

    function encodeVaaKey(VaaKey memory vaaKey) internal pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(vaaKey.chainId, vaaKey.emitterAddress, vaaKey.sequence);
    }

    function toWormholeFormat(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function encodeEvmExecutionParamsV1(
        EvmExecutionParamsV1 memory executionParams
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(ExecutionParamsVersion.EVM_V1), executionParams.gasLimit);
    }

    function getWormholeMessageFee() internal view returns (LocalNative) {
        return LocalNative.wrap(wormhole().messageFee());
    }
}
