//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SetUtil} from "@synthetixio/core-contracts/contracts/utils/SetUtil.sol";
import {IElectionInspectorModule} from "../../interfaces/IElectionInspectorModule.sol";
import {Ballot} from "../../storage/Ballot.sol";
import {Election} from "../../storage/Election.sol";

contract ElectionInspectorModule is IElectionInspectorModule {
    using SetUtil for SetUtil.AddressSet;
    using Ballot for Ballot.Data;

    function getEpochStartDateForIndex(uint256 epochIndex) external view override returns (uint64) {
        return Election.load(epochIndex).epoch.startDate;
    }

    function getEpochEndDateForIndex(uint256 epochIndex) external view override returns (uint64) {
        return Election.load(epochIndex).epoch.endDate;
    }

    function getNominationPeriodStartDateForIndex(
        uint256 epochIndex
    ) external view override returns (uint64) {
        return Election.load(epochIndex).epoch.nominationPeriodStartDate;
    }

    function getVotingPeriodStartDateForIndex(
        uint256 epochIndex
    ) external view override returns (uint64) {
        return Election.load(epochIndex).epoch.votingPeriodStartDate;
    }

    function wasNominated(
        address candidate,
        uint256 epochIndex
    ) external view override returns (bool) {
        return Election.load(epochIndex).nominees.contains(candidate);
    }

    function getNomineesAtEpoch(
        uint256 epochIndex
    ) external view override returns (address[] memory) {
        return Election.load(epochIndex).nominees.values();
    }

    function hasVotedInEpoch(
        address user,
        uint256 chainId,
        uint256 epochIndex
    ) external view override returns (bool) {
        return Ballot.load(epochIndex, user, chainId).hasVoted();
    }

    function getCandidateVotesInEpoch(
        address candidate,
        uint256 epochIndex
    ) external view override returns (uint) {
        return Election.load(epochIndex).candidateVoteTotals[candidate];
    }

    function getElectionWinnersInEpoch(
        uint256 epochIndex
    ) external view override returns (address[] memory) {
        return Election.load(epochIndex).winners.values();
    }
}
