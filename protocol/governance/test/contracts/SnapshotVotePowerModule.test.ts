import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import { fastForwardTo } from '@synthetixio/core-utils/utils/hardhat/rpc';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import assert from 'assert/strict';
import { ethers } from 'ethers';
import { bootstrap } from '../bootstrap';

describe('SnapshotVotePowerModule', function () {
  const { c, getSigners, getProvider } = bootstrap();

  let owner: ethers.Signer;
  let user: ethers.Signer;

  before('identify signers', function () {
    [owner, user] = getSigners();
  });

  const restore = snapshotCheckpoint(getProvider);

  describe('#setSnapshotContract', function () {
    before(restore);

    it('should revert when not owner', async function () {
      await assertRevert(
        c.CoreProxy.connect(user).setSnapshotContract(c.SnapshotRecordMock.address, true),
        `Unauthorized("${await user.getAddress()}"`,
        c.CoreProxy
      );
    });

    it('should not be valid until initialized', async function () {
      assert.equal(
        await c.CoreProxy.SnapshotVotePower_get_enabled(c.SnapshotRecordMock.address),
        false
      );
    });

    it('should set snapshot contract', async function () {
      await c.CoreProxy.setSnapshotContract(c.SnapshotRecordMock.address, true);
      assert.equal(
        await c.CoreProxy.SnapshotVotePower_get_enabled(c.SnapshotRecordMock.address),
        true
      );
    });

    it('should unset snapshot contract', async function () {
      await c.CoreProxy.setSnapshotContract(c.SnapshotRecordMock.address, false);
      assert.equal(
        await c.CoreProxy.SnapshotVotePower_get_enabled(c.SnapshotRecordMock.address),
        false
      );
    });
  });

  describe('#takeVotePowerSnapshot', function () {
    before(restore);

    const disabledSnapshotContract = ethers.Wallet.createRandom().address;
    before('setup snapshot contracts', async function () {
      // setup main snapshot contract
      await c.CoreProxy.setSnapshotContract(c.SnapshotRecordMock.address, true);

      // setup and disable an snapshot contract
      await c.CoreProxy.setSnapshotContract(disabledSnapshotContract, true);
      await c.CoreProxy.setSnapshotContract(disabledSnapshotContract, false);
    });

    it('should revert when not correct epoch phase', async function () {
      await assertRevert(
        c.CoreProxy.takeVotePowerSnapshot(c.SnapshotRecordMock.address),
        'NotCallableInCurrentPeriod',
        c.CoreProxy
      );
    });

    describe('advance time to nomination phase', function () {
      before('advance time', async function () {
        const settings = await c.CoreProxy.getEpochSchedule();
        await fastForwardTo(settings.nominationPeriodStartDate.toNumber(), getProvider());
      });

      it('should revert when using invalid snapshot contract', async function () {
        await assertRevert(
          c.CoreProxy.takeVotePowerSnapshot(ethers.Wallet.createRandom().address),
          'InvalidSnapshotContract',
          c.CoreProxy
        );
      });

      it('should revert when using disabled snapshot contract', async function () {
        await assertRevert(
          c.CoreProxy.takeVotePowerSnapshot(disabledSnapshotContract),
          'InvalidSnapshotContract',
          c.CoreProxy
        );
      });

      it('should take vote power snapshot', async function () {
        assertBn.equal(
          await c.CoreProxy.getVotePowerSnapshotId(
            c.SnapshotRecordMock.address,
            await c.CoreProxy.Council_get_currentElectionId()
          ),
          0
        );
        await c.CoreProxy.takeVotePowerSnapshot(c.SnapshotRecordMock.address);
        assertBn.gt(
          await c.CoreProxy.getVotePowerSnapshotId(
            c.SnapshotRecordMock.address,
            await c.CoreProxy.Council_get_currentElectionId()
          ),
          0
        );
      });

      it('should fail with snapshot already taken if we repeat', async function () {
        await assertRevert(
          c.CoreProxy.takeVotePowerSnapshot(c.SnapshotRecordMock.address),
          'SnapshotAlreadyTaken',
          c.CoreProxy
        );
      });
    });
  });

  describe('#prepareBallotWithSnapshot', function () {
    before(restore);

    const disabledSnapshotContract = ethers.Wallet.createRandom().address;

    before('setup disabled snapshot contract', async function () {
      // setup and disable an snapshot contract
      await c.CoreProxy.setSnapshotContract(disabledSnapshotContract, true);
      await c.CoreProxy.setSnapshotContract(disabledSnapshotContract, false);
    });

    before('set snapshot contract', async function () {
      await c.CoreProxy.setSnapshotContract(c.SnapshotRecordMock.address, true);
      const settings = await c.CoreProxy.getEpochSchedule();
      await fastForwardTo(settings.nominationPeriodStartDate.toNumber(), getProvider());
      await c.CoreProxy.takeVotePowerSnapshot(c.SnapshotRecordMock.address);

      const snapshotId = await c.CoreProxy.getVotePowerSnapshotId(
        c.SnapshotRecordMock.address,
        await c.CoreProxy.Council_get_currentElectionId()
      );

      await c.SnapshotRecordMock.setBalanceOfOnPeriod(await user.getAddress(), 100, snapshotId);
    });

    it('cannot prepare ballot before voting starts', async function () {
      await assertRevert(
        c.CoreProxy.connect(owner).prepareBallotWithSnapshot(
          c.SnapshotRecordMock.address,
          await user.getAddress()
        ),
        'NotCallableInCurrentPeriod',
        c.CoreProxy
      );
    });

    describe('advance to voting period', function () {
      before('advance time', async function () {
        const settings = await c.CoreProxy.getEpochSchedule();
        await fastForwardTo(settings.votingPeriodStartDate.toNumber(), getProvider());
      });

      it('should revert when using disabled snapshot contract', async function () {
        await assertRevert(
          c.CoreProxy.prepareBallotWithSnapshot(disabledSnapshotContract, await user.getAddress()),
          'InvalidSnapshotContract',
          c.CoreProxy
        );
      });

      it('should create an empty ballot with voting power for specified user', async function () {
        const foundVotingPower = await c.CoreProxy.connect(
          owner
        ).callStatic.prepareBallotWithSnapshot(
          c.SnapshotRecordMock.address,
          await user.getAddress()
        );
        await c.CoreProxy.connect(owner).prepareBallotWithSnapshot(
          c.SnapshotRecordMock.address,
          await user.getAddress()
        );

        assertBn.equal(foundVotingPower, 100);

        const ballotVotingPower = await c.CoreProxy.Ballot_get_votingPower(
          await c.CoreProxy.Council_get_currentElectionId(),
          await user.getAddress(),
          13370 // precinct is current chain id
        );

        assertBn.equal(ballotVotingPower, 100);
      });
    });
  });
});