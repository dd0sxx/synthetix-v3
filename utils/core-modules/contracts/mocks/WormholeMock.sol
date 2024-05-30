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

    uint256 public immutable CHAIN_ID;

    constructor(uint256 chainId) {
        CHAIN_ID = chainId;
    }

    mapping(address => uint64) public sequences;

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence) {
        sequence = sequences[msg.sender]++; //TODO should this be tx.origin instead of msg.sender?
        emit LogMessagePublished(msg.sender, sequence, nonce, payload, consistencyLevel);
    }

    function messageFee() external pure returns (uint256) {
        return 0;
    }

    function chainId() external view returns (uint256) {
        return CHAIN_ID;
    }
}
