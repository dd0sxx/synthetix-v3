//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "../../interfaces/IElectionModule.sol";
import "../../interfaces/ISynthetixElectionModule.sol";
import "../../submodules/election/DebtShareManager.sol";
import "../../submodules/election/CrossChainDebtShareManager.sol";
import "./BaseElectionModule.sol";

/// @title Module for electing a council, represented by a set of NFT holders
/// @notice This extends the base ElectionModule by determining voting power by Synthetix v2 debt share
contract ElectionModule is
    ISynthetixElectionModule,
    DebtShareManager,
    CrossChainDebtShareManager,
    BaseElectionModule
{
    using SafeCastU256 for uint256;

    error TooManyCandidates();
    error WrongInitializer();

    /// @dev The BaseElectionModule initializer should not be called, and this one must be called instead
    function initOrUpgradeElectionModule(
        address[] memory,
        uint8,
        uint8,
        uint64,
        uint64,
        uint64
    ) external view override(BaseElectionModule, IElectionModule) {
        OwnableStorage.onlyOwner();
        revert WrongInitializer();
    }

    /// @dev Overloads the BaseElectionModule initializer with an additional parameter for the debt share contract
    function initOrUpgradeElectionModule(
        address[] memory firstCouncil,
        uint8 minimumActiveMembers,
        uint8 epochSeatCount,
        uint64 nominationPeriodStartDate,
        uint16 votingPeriodDuration,
        uint16 epochDuration,
        address debtShareContract
    ) external override {
        OwnableStorage.onlyOwner();

        if (Council.load().initialized) {
            return;
        }

        _setDebtShareContract(debtShareContract);

        if (nominationPeriodStartDate == 0) {
            nominationPeriodStartDate = block.timestamp.to64() + (86400 * votingPeriodDuration);
        }

        uint64 votingPeriodStartDate = nominationPeriodStartDate + (86400 * votingPeriodDuration);
        uint64 epochEndDate = nominationPeriodStartDate + (86400 * epochDuration);

        _initOrUpgradeElectionModule(
            firstCouncil,
            minimumActiveMembers,
            epochSeatCount,
            nominationPeriodStartDate,
            votingPeriodStartDate,
            epochEndDate
        );
    }

    /// @dev Overrides the BaseElectionModule nominate function to only allow 1 candidate to be nominated
    function cast(
        address[] calldata candidates
    )
        public
        override(BaseElectionModule, IElectionModule)
        onlyInPeriod(Council.ElectionPeriod.Vote)
    {
        if (candidates.length > 1) {
            revert TooManyCandidates();
        }

        super.cast(candidates);
    }

    // ---------------------------------------
    // Debt shares
    // ---------------------------------------

    function setDebtShareContract(
        address debtShareContract
    ) external override onlyInPeriod(Council.ElectionPeriod.Administration) {
        OwnableStorage.onlyOwner();

        _setDebtShareContract(debtShareContract);

        emit DebtShareContractSet(debtShareContract);
    }

    function getDebtShareContract() external view override returns (address) {
        return _getDebtShareContract();
    }

    function setDebtShareSnapshotId(
        uint snapshotId
    ) external override onlyInPeriod(Council.ElectionPeriod.Nomination) {
        OwnableStorage.onlyOwner();
        _setDebtShareSnapshotId(snapshotId);
    }

    function getDebtShareSnapshotId() external view override returns (uint) {
        return _getDebtShareSnapshotId();
    }

    function getDebtShare(address user) external view override returns (uint) {
        return _getDebtShare(user);
    }

    // ---------------------------------------
    // Cross chain debt shares
    // ---------------------------------------

    function setCrossChainDebtShareMerkleRoot(
        bytes32 merkleRoot,
        uint blocknumber
    ) external override onlyInPeriod(Council.ElectionPeriod.Nomination) {
        OwnableStorage.onlyOwner();
        _setCrossChainDebtShareMerkleRoot(merkleRoot, blocknumber);

        emit CrossChainDebtShareMerkleRootSet(
            merkleRoot,
            blocknumber,
            Council.load().lastElectionId
        );
    }

    function getCrossChainDebtShareMerkleRoot() external view override returns (bytes32) {
        return _getCrossChainDebtShareMerkleRoot();
    }

    function getCrossChainDebtShareMerkleRootBlockNumber() external view override returns (uint) {
        return _getCrossChainDebtShareMerkleRootBlockNumber();
    }

    function declareCrossChainDebtShare(
        address user,
        uint256 debtShare,
        bytes32[] calldata merkleProof
    ) public override onlyInPeriod(Council.ElectionPeriod.Vote) {
        _declareCrossChainDebtShare(user, debtShare, merkleProof);

        emit CrossChainDebtShareDeclared(user, debtShare);
    }

    function getDeclaredCrossChainDebtShare(address user) external view override returns (uint) {
        return _getDeclaredCrossChainDebtShare(user);
    }

    function declareAndCast(
        uint256 debtShare,
        bytes32[] calldata merkleProof,
        address[] calldata candidates
    ) public override onlyInPeriod(Council.ElectionPeriod.Vote) {
        declareCrossChainDebtShare(msg.sender, debtShare, merkleProof);

        cast(candidates);
    }

    // ---------------------------------------
    // Internal
    // ---------------------------------------

    function _sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @dev Overrides the user's voting power by combining local chain debt share with debt shares in other chains, quadratically filtered
    function _getVotePower(address user) internal view virtual override returns (uint) {
        uint votePower = _getDebtShare(user) + _getDeclaredCrossChainDebtShare(user);

        return _sqrt(votePower);
    }
}
