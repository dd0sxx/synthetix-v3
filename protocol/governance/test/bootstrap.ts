import { coreBootstrap } from '@synthetixio/router/dist/utils/tests';
import hre from 'hardhat';

import type { CoreProxy, CouncilToken, SnapshotRecordMock } from './generated/typechain';

interface Contracts {
  CoreProxy: CoreProxy;
  CouncilToken: CouncilToken;
  CouncilTokenRouter: CouncilToken;
  SnapshotRecordMock: SnapshotRecordMock;
}

const { getProvider, getSigners, getContract, createSnapshot } = coreBootstrap<Contracts>({
  cannonfile: 'cannonfile.test.toml',
} as { cannonfile: string });

function snapshotCheckpoint() {
  const restoreSnapshot = createSnapshot();
  after('restore snapshot', restoreSnapshot);
}

export function bootstrap() {
  const contracts: Partial<Contracts> = {};
  const c = contracts as Contracts;

  snapshotCheckpoint();

  before('load contracts', function () {
    Object.assign(contracts, {
      CoreProxy: getContract('CoreProxy'),
      CouncilToken: getContract('CouncilToken'),
      CouncilTokenRouter: getContract('CouncilTokenRouter'),
      SnapshotRecordMock: getContract('SnapshotRecordMock'),
    });
  });

  return {
    c,
    getProvider,
    getSigners,
    getContract,
    snapshotCheckpoint,

    async deployNewProxy(implementation?: string) {
      const [owner] = getSigners();
      const factory = await hre.ethers.getContractFactory('Proxy', owner);
      const NewProxy = await factory.deploy(
        implementation || (await c.CoreProxy.getImplementation()),
        await owner.getAddress()
      );
      return c.CoreProxy.attach(NewProxy.address);
    },
  };
}
