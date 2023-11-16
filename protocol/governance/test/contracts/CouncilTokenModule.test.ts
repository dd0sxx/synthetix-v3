import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import { ethers } from 'ethers';
import { bootstrap } from '../bootstrap';
import { CouncilTokenModule } from '../generated/typechain/CouncilTokenModule';

describe('CouncilTokenModule', function () {
  const { c, getSigners, deployNewProxy } = bootstrap();

  let user1: ethers.Signer;
  let user2: ethers.Signer;
  let CouncilToken: CouncilTokenModule;

  before('identify signers', async function () {
    [, user1, user2] = getSigners();
  });

  before('deploy new council token router', async function () {
    // create a new Proxy with our implementation of the CouncilToken so we can test it isolated
    CouncilToken = await deployNewProxy(c.CouncilTokenRouter.address);
  });

  it('can mint council nfts', async function () {
    await CouncilToken.mint(await user1.getAddress(), 1);
    await CouncilToken.mint(await user2.getAddress(), 2);
  });

  it('can burn council nfts', async function () {
    await CouncilToken.burn(1);
    await CouncilToken.burn(2);
  });

  it('reverts when trying to transfer', async function () {
    await CouncilToken.mint(await user1.getAddress(), 3);

    await assertRevert(
      CouncilToken.connect(user1).transferFrom(
        await user1.getAddress(),
        await user2.getAddress(),
        3
      ),
      'NotImplemented()'
    );
  });
});