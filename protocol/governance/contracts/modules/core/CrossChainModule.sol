//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {CrossChainModule as BaseCrossChainModule} from "@synthetixio/core-modules/contracts/modules/CrossChainModule.sol";

/**
 * @title Module that handles anything related to cross-chain.
 */
// solhint-disable-next-line no-empty-blocks
contract CrossChainModule is BaseCrossChainModule {
    function sendCrossChainMessage(
        Data storage self,
        bytes memory data
    ) public payable returns (uint64 messageSequence) {
        uint256 cost = self.wormholeRelayer.messageFee();
        require(msg.value == cost, "Incorrect payment");

        bytes memory payload = abi.encode(data, ERC2771Context._msgSender());

        self.wormholeRelayer.publishMessage{value: cost}(
            self.nonce,
            payload,
            1 // consistencyLevel or wormholeFinality
        );
        self.nonce++;
    }

    function receiveWormholeMessages(Data storage self, bytes memory encodedMessage) external {
        (IWormhole.VM memory wormholeMessage, bool valid, string memory reason) = self
            .wormholeRelayer
            .parseAndVerifyVM(encodedMessage);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by a registered emitter
        require(verifyEmitter(wormholeMessage), "unknown emitter");

        // TODO: what are we actually doing with the message?
    }
}
