//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract WormholeMock {
    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    mapping(address => uint64) public sequences;

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence) {
        sequence = sequences[msg.sender]++;
        emit LogMessagePublished(msg.sender, sequence, nonce, payload, consistencyLevel);
    }

    function messageFee() external pure returns (uint256) {
        return 0;
    }

    function chainId() external pure returns (uint256) {
        return 1;
    }
}
