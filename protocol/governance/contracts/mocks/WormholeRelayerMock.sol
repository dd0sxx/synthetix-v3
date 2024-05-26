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

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes payload;
        TargetNative requestedReceiverValue;
        TargetNative extraReceiverValue;
        bytes encodedExecutionInfo;
        uint16 refundChain;
        bytes32 refundAddress;
        bytes32 refundDeliveryProvider;
        bytes32 sourceDeliveryProvider;
        bytes32 senderAddress;
        MessageKey[] messageKeys;
    }

    struct EvmExecutionParamsV1 {
        Gas gasLimit;
    }

    enum ExecutionParamsVersion {
        EVM_V1
    }

    event SendEvent(
        uint64 indexed sequence,
        LocalNative deliveryQuote,
        LocalNative paymentForExtraReceiverValue
    );

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

        // Obtain the delivery provider's fee for this delivery, as well as some encoded info (e.g. refund per unit of gas unused)
        (uint256 deliveryPrice, bytes memory encodedExecutionInfo) = provider.quoteDeliveryPrice(
            sendParams.targetChain,
            TargetNative.unwrap(sendParams.receiverValue),
            sendParams.encodedExecutionParameters
        );

        // Check if user passed in 'one wormhole message fee' + 'delivery provider's fee'
        LocalNative wormholeMessageFee = getWormholeMessageFee();

        // Encode all relevant info the delivery provider needs to perform the delivery as requested
        bytes memory encodedInstruction = abi.encode(
            DeliveryInstruction({
                targetChain: sendParams.targetChain,
                targetAddress: sendParams.targetAddress,
                payload: sendParams.payload,
                requestedReceiverValue: sendParams.receiverValue,
                extraReceiverValue: TargetNative.wrap(
                    provider.quoteAssetConversion(
                        sendParams.targetChain,
                        LocalNative.unwrap(sendParams.paymentForExtraReceiverValue)
                    )
                ),
                encodedExecutionInfo: encodedExecutionInfo,
                refundChain: sendParams.refundChain,
                refundAddress: sendParams.refundAddress,
                refundDeliveryProvider: provider.getTargetChainAddress(sendParams.targetChain),
                sourceDeliveryProvider: toWormholeFormat(sendParams.deliveryProviderAddress),
                senderAddress: toWormholeFormat(msg.sender),
                messageKeys: sendParams.messageKeys
            })
        );

        // Publish the encoded delivery instruction as a wormhole message
        // and pay the delivery provider their fee
        bool paymentSucceeded;
        (sequence, paymentSucceeded) = publishAndPay(
            wormholeMessageFee,
            LocalNative.wrap(deliveryPrice),
            sendParams.paymentForExtraReceiverValue,
            encodedInstruction,
            sendParams.consistencyLevel,
            provider.getRewardAddress()
        );

        if (!paymentSucceeded) {
            revert DeliveryProviderCannotReceivePayment();
        }
    }

    function publishAndPay(
        LocalNative wormholeMessageFee,
        LocalNative deliveryQuote,
        LocalNative paymentForExtraReceiverValue,
        bytes memory encodedInstruction,
        uint8 consistencyLevel,
        address payable rewardAddress
    ) internal returns (uint64 sequence, bool paymentSucceeded) {
        sequence = wormhole.publishMessage{value: LocalNative.unwrap(wormholeMessageFee)}(
            0,
            encodedInstruction,
            consistencyLevel
        );

        paymentSucceeded = pay(
            rewardAddress,
            LocalNative.wrap(
                LocalNative.unwrap(deliveryQuote) + LocalNative.unwrap(paymentForExtraReceiverValue)
            )
        );

        emit SendEvent(sequence, deliveryQuote, paymentForExtraReceiverValue);
    }

    function pay(address payable receiver, LocalNative amount) internal returns (bool success) {
        uint256 amount_ = LocalNative.unwrap(amount);
        if (amount_ != 0) (success, ) = receiver.call{gas: gasleft(), value: amount_}(new bytes(0));
        else success = true;
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
        return LocalNative.wrap(wormhole.messageFee());
    }

    function msgValue() internal view returns (LocalNative) {
        return LocalNative.wrap(msg.value);
    }
}
