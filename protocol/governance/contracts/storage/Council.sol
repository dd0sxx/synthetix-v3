//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@synthetixio/core-contracts/contracts/utils/SetUtil.sol";
import "./Election.sol";
import "./ElectionSettings.sol";

library Council {
    bytes32 private constant _SLOT_COUNCIL_STORAGE =
        keccak256(abi.encode("io.synthetix.governance.Council"));

    struct Data {
        // True if initializeElectionModule was called
        bool initialized;
        // The address of the council NFT
        address councilToken;
        // Council member addresses
        SetUtil.AddressSet councilMembers;
        // Council token id's by council member address
        mapping(address => uint) councilTokenIds;
        // id of the last election
        uint lastElectionId;
    }

    enum ElectionPeriod {
        // Council elected and active
        Administration,
        // Accepting nominations for next election
        Nomination,
        // Accepting votes for ongoing election
        Vote,
        // Votes being counted
        Evaluation
    }

    function load() internal pure returns (Data storage store) {
        bytes32 s = _SLOT_COUNCIL_STORAGE;
        assembly {
            store.slot := s
        }
    }

    function newElection(Data storage self) internal returns (uint) {
        return ++self.lastElectionId;
    }

    function getCurrentElection(
        Data storage self
    ) internal view returns (Election.Data storage election) {
        return Election.load(self.lastElectionId);
    }

    function getPreviousElection(
        Data storage self
    ) internal view returns (Election.Data storage election) {
        // NOTE: will revert if there was no previous election
        return Election.load(self.lastElectionId - 1);
    }

    function getCurrentElectionSettings(
        Data storage self
    ) internal view returns (ElectionSettings.Data storage settings) {
        return ElectionSettings.load(self.lastElectionId);
    }

    function getPreviousElectionSettings(
        Data storage self
    ) internal view returns (ElectionSettings.Data storage settings) {
        // NOTE: will revert if there was no previous settings
        return ElectionSettings.load(self.lastElectionId - 1);
    }

    /// @dev Determines the current period type according to the current time and the epoch's dates
    function getCurrentPeriod(Data storage self) internal view returns (Council.ElectionPeriod) {
        Epoch.Data storage epoch = getCurrentElection(self).epoch;

        // solhint-disable-next-line numcast/safe-cast
        uint64 currentTime = uint64(block.timestamp);

        if (currentTime >= epoch.endDate) {
            return Council.ElectionPeriod.Evaluation;
        }

        if (currentTime >= epoch.votingPeriodStartDate) {
            return Council.ElectionPeriod.Vote;
        }

        if (currentTime >= epoch.nominationPeriodStartDate) {
            return Council.ElectionPeriod.Nomination;
        }

        return Council.ElectionPeriod.Administration;
    }
}
