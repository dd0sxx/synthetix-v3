//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@synthetixio/core-contracts/contracts/errors/InitError.sol";
import "@synthetixio/core-contracts/contracts/errors/ParameterError.sol";
import "@synthetixio/core-contracts/contracts/initializable/InitializableMixin.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import "@synthetixio/main/contracts/storage/CrossChain.sol";
import "@synthetixio/core-contracts/contracts/proxy/ProxyStorage.sol";
import "../../interfaces/IElectionModule.sol";
import "../../submodules/election/ElectionSettingsManager.sol";
import "../../submodules/election/ElectionSchedule.sol";
import "../../submodules/election/ElectionCredentials.sol";
import "../../submodules/election/ElectionVotes.sol";
import "../../submodules/election/ElectionTally.sol";

contract BaseElectionModule is
    IElectionModule,
    ElectionSettingsManager,
    ElectionSchedule,
    ElectionCredentials,
    ElectionVotes,
    ElectionTally,
    InitializableMixin,
    ProxyStorage
{
    using SetUtil for SetUtil.AddressSet;
    using Council for Council.Data;
    using CrossChain for CrossChain.Data;
    using SafeCastU256 for uint256;

    uint256 private constant _CROSSCHAIN_GAS_LIMIT = 100000;

    /// @dev Used to allow certain functions to only be configured on the "mothership" chain.
    modifier onlyMothership() {
        if (CrossChain.load().mothershipChainId != block.chainid.to64()) {
            revert NotMothership();
        }

        _;
    }

    function initOrUpgradeElectionModule(
        address[] memory firstCouncil,
        uint8 epochSeatCount,
        uint8 minimumActiveMembers,
        uint64 nominationPeriodStartDate,
        uint64 votingPeriodStartDate,
        uint64 epochEndDate,
        uint64 maxDateAdjustmentTolerance
    ) external virtual override onlyIfNotInitialized {
        OwnableStorage.onlyOwner();

        _initOrUpgradeElectionModule(
            firstCouncil,
            epochSeatCount,
            minimumActiveMembers,
            nominationPeriodStartDate,
            votingPeriodStartDate,
            epochEndDate,
            maxDateAdjustmentTolerance
        );
    }

    function _initOrUpgradeElectionModule(
        address[] memory firstCouncil,
        uint8 epochSeatCount,
        uint8 minimumActiveMembers,
        uint64 nominationPeriodStartDate,
        uint64 votingPeriodStartDate,
        uint64 epochEndDate,
        uint64 maxDateAdjustmentTolerance
    ) internal {
        Council.Data storage store = Council.load();

        uint64 epochStartDate = block.timestamp.to64();

        ElectionSettings.Data storage settings = store.getCurrentElectionSettings();
        _setElectionSettings(
            settings,
            epochSeatCount,
            minimumActiveMembers,
            epochEndDate - epochStartDate, // epochDuration
            votingPeriodStartDate - nominationPeriodStartDate, // nominationPeriodDuration
            epochEndDate - votingPeriodStartDate, // votingPeriodDuration
            maxDateAdjustmentTolerance
        );

        // Set current implementation (see UpgradeProposalModule)
        settings.proposedImplementation = _proxyStore().implementation;

        _copyMissingSettings(settings, store.getNextElectionSettings());

        Epoch.Data storage firstEpoch = store.getCurrentElection().epoch;

        _configureEpochSchedule(
            firstEpoch,
            epochStartDate,
            nominationPeriodStartDate,
            votingPeriodStartDate,
            epochEndDate
        );

        _addCouncilMembers(firstCouncil, 0);

        store.initialized = true;

        emit ElectionModuleInitialized();
        emit EpochStarted(0);
    }

    function isElectionModuleInitialized() public view override returns (bool) {
        return _isInitialized();
    }

    function _isInitialized() internal view override returns (bool) {
        return Council.load().initialized;
    }

    function configureMothership(
        uint64 mothershipChainId
    ) external onlyInPeriod(Council.ElectionPeriod.Administration) returns (uint256 gasTokenUsed) {
        OwnableStorage.onlyOwner();

        if (mothershipChainId == 0) {
            revert ParameterError.InvalidParameter("mothershipChainId", "must be nonzero");
        }

        CrossChain.Data storage cc = CrossChain.load();
        gasTokenUsed = cc.broadcast(
            cc.getSupportedNetworks(),
            abi.encodeWithSelector(this._recvConfigureMothership.selector, cc.mothershipChainId),
            _CROSSCHAIN_GAS_LIMIT
        );
    }

    function _recvConfigureMothership(uint64 mothershipChainId) external {
        CrossChain.onlyCrossChain();
        CrossChain.load().mothershipChainId = mothershipChainId;

        emit MothershipChainIdUpdated(mothershipChainId);
    }

    function tweakEpochSchedule(
        uint64 newNominationPeriodStartDate,
        uint64 newVotingPeriodStartDate,
        uint64 newEpochEndDate
    ) external override onlyInPeriod(Council.ElectionPeriod.Administration) {
        OwnableStorage.onlyOwner();
        _adjustEpochSchedule(
            Council.load().getCurrentElection().epoch,
            newNominationPeriodStartDate,
            newVotingPeriodStartDate,
            newEpochEndDate,
            true /*ensureChangesAreSmall = true*/
        );

        emit EpochScheduleUpdated(
            newNominationPeriodStartDate,
            newVotingPeriodStartDate,
            newEpochEndDate
        );
    }

    function setNextElectionSettings(
        uint8 epochSeatCount,
        uint8 minimumActiveMembers,
        uint64 epochDuration,
        uint64 nominationPeriodDuration,
        uint64 votingPeriodDuration,
        uint64 maxDateAdjustmentTolerance
    ) external override onlyInPeriod(Council.ElectionPeriod.Administration) {
        OwnableStorage.onlyOwner();

        _setElectionSettings(
            Council.load().getNextElectionSettings(),
            epochSeatCount,
            minimumActiveMembers,
            epochDuration,
            nominationPeriodDuration,
            votingPeriodDuration,
            maxDateAdjustmentTolerance
        );
    }

    function dismissMembers(address[] calldata membersToDismiss) external override {
        OwnableStorage.onlyOwner();

        Council.Data storage store = Council.load();

        uint epochIndex = store.lastElectionId;

        _removeCouncilMembers(membersToDismiss, epochIndex);

        emit CouncilMembersDismissed(membersToDismiss, epochIndex);

        if (store.getCurrentPeriod() != Council.ElectionPeriod.Administration) return;

        // Don't immediately jump to an election if the council still has enough members
        if (
            store.councilMembers.length() >= store.getCurrentElectionSettings().minimumActiveMembers
        ) {
            return;
        }

        _jumpToNominationPeriod();

        emit EmergencyElectionStarted(epochIndex);
    }

    function nominate() public virtual override onlyInPeriod(Council.ElectionPeriod.Nomination) {
        SetUtil.AddressSet storage nominees = Council.load().getCurrentElection().nominees;

        if (nominees.contains(msg.sender)) revert AlreadyNominated();

        nominees.add(msg.sender);

        emit CandidateNominated(msg.sender, Council.load().lastElectionId);

        // TODO: add ballot id to emitted event
    }

    function withdrawNomination()
        external
        override
        onlyInPeriod(Council.ElectionPeriod.Nomination)
    {
        SetUtil.AddressSet storage nominees = Council.load().getCurrentElection().nominees;

        if (!nominees.contains(msg.sender)) revert NotNominated();

        nominees.remove(msg.sender);

        emit NominationWithdrawn(msg.sender, Council.load().lastElectionId);
    }

    /// @dev ElectionVotes needs to be extended to specify what determines voting power
    function cast(
        address[] calldata candidates
    ) public virtual override onlyInPeriod(Council.ElectionPeriod.Vote) {
        CrossChain.Data storage cc = CrossChain.load();
        cc.transmit(
            cc.mothershipChainId,
            abi.encodeWithSelector(this._recvCast.selector, candidates),
            _CROSSCHAIN_GAS_LIMIT
        );
    }

    function _recvCast(
        address[] calldata candidates
    ) external onlyInPeriod(Council.ElectionPeriod.Vote) onlyMothership {
        uint votePower = _getVotePower(msg.sender);

        if (votePower == 0) revert NoVotePower();

        _validateCandidates(candidates);

        bytes32 ballotId;

        uint epochIndex = Council.load().lastElectionId;

        if (hasVoted(msg.sender)) {
            _withdrawCastedVote(msg.sender, epochIndex);
        }

        ballotId = _recordVote(msg.sender, votePower, candidates);

        emit VoteRecorded(msg.sender, ballotId, epochIndex, votePower);
    }

    function withdrawVote() external override onlyInPeriod(Council.ElectionPeriod.Vote) {
        if (!hasVoted(msg.sender)) {
            revert VoteNotCasted();
        }

        _withdrawCastedVote(msg.sender, Council.load().lastElectionId);
    }

    /// @dev ElectionTally needs to be extended to specify how votes are counted
    function evaluate(
        uint numBallots
    ) external override onlyInPeriod(Council.ElectionPeriod.Evaluation) onlyMothership {
        Election.Data storage election = Council.load().getCurrentElection();

        if (election.evaluated) revert ElectionAlreadyEvaluated();

        _evaluateNextBallotBatch(numBallots);

        uint currentEpochIndex = Council.load().lastElectionId;

        uint totalBallots = election.ballotIds.length;
        if (election.numEvaluatedBallots < totalBallots) {
            emit ElectionBatchEvaluated(
                currentEpochIndex,
                election.numEvaluatedBallots,
                totalBallots
            );
        } else {
            election.evaluated = true;
            emit ElectionEvaluated(currentEpochIndex, totalBallots);
        }
    }

    /// @dev Burns previous NFTs and mints new ones
    function resolve()
        public
        virtual
        override
        onlyInPeriod(Council.ElectionPeriod.Evaluation)
        onlyMothership
    {
        Council.Data storage store = Council.load();
        Election.Data storage election = store.getCurrentElection();

        if (!election.evaluated) revert ElectionNotEvaluated();

        uint newEpochIndex = store.lastElectionId + 1;

        _removeAllCouncilMembers(newEpochIndex);
        _addCouncilMembers(election.winners.values(), newEpochIndex);

        election.resolved = true;

        store.newElection();

        _copyMissingSettings(store.getCurrentElectionSettings(), store.getNextElectionSettings());
        _initScheduleFromSettings();

        emit EpochStarted(newEpochIndex);

        // TODO: Broadcast message to distribute the new NFTs on all chains
    }

    function getEpochSchedule() external view override returns (Epoch.Data memory epoch) {
        return Council.load().getCurrentElection().epoch;
    }

    function getElectionSettings()
        external
        view
        override
        returns (ElectionSettings.Data memory settings)
    {
        return Council.load().getCurrentElectionSettings();
    }

    function getNextElectionSettings()
        external
        view
        override
        returns (ElectionSettings.Data memory settings)
    {
        return Council.load().getNextElectionSettings();
    }

    function getEpochIndex() external view override returns (uint) {
        return Council.load().lastElectionId;
    }

    function getCurrentPeriod() external view override returns (uint) {
        // solhint-disable-next-line numcast/safe-cast
        return uint(Council.load().getCurrentPeriod());
    }

    function isNominated(address candidate) external view override returns (bool) {
        return Council.load().getCurrentElection().nominees.contains(candidate);
    }

    function getNominees() external view override returns (address[] memory) {
        return Council.load().getCurrentElection().nominees.values();
    }

    function calculateBallotId(
        address[] calldata candidates
    ) external pure override returns (bytes32) {
        return keccak256(abi.encode(candidates));
    }

    function getBallotVoted(address user) public view override returns (bytes32) {
        return Council.load().getCurrentElection().ballotIdsByAddress[user];
    }

    function hasVoted(address user) public view override returns (bool) {
        return Council.load().getCurrentElection().ballotIdsByAddress[user] != bytes32(0);
    }

    function getVotePower(address user) external view override returns (uint) {
        return _getVotePower(user);
    }

    function getBallotVotes(bytes32 ballotId) external view override returns (uint) {
        return Council.load().getCurrentElection().ballotsById[ballotId].votes;
    }

    function getBallotCandidates(
        bytes32 ballotId
    ) external view override returns (address[] memory) {
        return Council.load().getCurrentElection().ballotsById[ballotId].candidates;
    }

    function isElectionEvaluated() public view override returns (bool) {
        return Council.load().getCurrentElection().evaluated;
    }

    function getCandidateVotes(address candidate) external view override returns (uint) {
        return Council.load().getCurrentElection().candidateVotes[candidate];
    }

    function getElectionWinners() external view override returns (address[] memory) {
        return Council.load().getCurrentElection().winners.values();
    }

    function getCouncilToken() public view override returns (address) {
        return Council.load().councilToken;
    }

    function getCouncilMembers() external view override returns (address[] memory) {
        return Council.load().councilMembers.values();
    }
}
