import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import { findSingleEvent } from '@synthetixio/core-utils/utils/ethers/events';
import assert from 'assert/strict';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { bootstrap } from '../bootstrap';
import { DebtShareMock } from '../generated/typechain';

describe('SynthetixElectionModule - DebtShare', function () {
  const { c, getSigners } = bootstrap();

  let owner: ethers.Signer;

  before('identify signers', async function () {
    [owner] = getSigners();
  });

  describe('when the election module is initialized', function () {
    it('shows that the DebtShare contract is connected', async function () {
      assert.equal(await c.CoreProxy.getDebtShareContract(), c.DebtShareMock.address);
    });

    describe('when re setting the debt share contract', function () {
      describe('with the same address', function () {
        it('reverts', async function () {
          await assertRevert(c.CoreProxy.setDebtShareContract(c.DebtShareMock.address), 'NoChange');
        });
      });

      describe('with an invalid address', function () {
        it('reverts', async function () {
          await assertRevert(
            c.CoreProxy.setDebtShareContract(ethers.constants.AddressZero),
            'ZeroAddress'
          );
        });
      });

      describe('with an EOA', function () {
        it('reverts', async function () {
          await assertRevert(
            c.CoreProxy.setDebtShareContract(await owner.getAddress()),
            'NotAContract'
          );
        });
      });

      describe('with a different address', function () {
        let DebtShare: DebtShareMock;
        let receipt: ethers.ContractReceipt;

        before('deploy debt shares mock', async function () {
          const factory = await hre.ethers.getContractFactory('DebtShareMock');
          DebtShare = await factory.deploy();
        });

        before('set the new debt share contract', async function () {
          const tx = await c.CoreProxy.setDebtShareContract(DebtShare.address);
          receipt = await tx.wait();
        });

        it('emitted a DebtShareContractSet event', async function () {
          const event = findSingleEvent({ receipt, eventName: 'DebtShareContractSet' });
          assert.ok(event);
          assertBn.equal(event.args.contractAddress, DebtShare.address);
        });

        it('shows that the DebtShare contract is connected', async function () {
          assert.equal(await c.CoreProxy.getDebtShareContract(), DebtShare.address);
        });
      });
    });
  });
});
