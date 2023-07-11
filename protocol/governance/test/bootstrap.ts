import { coreBootstrap } from '@synthetixio/router/dist/utils/tests';

import type {
  CoreProxy,
  AccountProxy,
  CoreRouter,
  DebtShareMock,
  CouncilTokenRouter,
} from './generated/typechain';

interface Contracts {
  CoreRouter: CoreRouter;
  CoreProxy: CoreProxy;
  AccountProxy: AccountProxy;
  CouncilTokenRouter: CouncilTokenRouter;
  DebtShareMock: DebtShareMock;
}

const { getProvider, getSigners, getContract, createSnapshot } = coreBootstrap<Contracts>({
  cannonfile: 'cannonfile.test.toml',
  // Use always the same year to allow to cache the cannon build. If we leave the default
  // value it will use block.timestamp and generate a new build each time.
  settings: [
    `initial_epoch_start=${Math.floor(new Date(new Date().getFullYear() + 2, 0).valueOf() / 1000)}`,
  ],
} as { cannonfile: string });

const restoreSnapshot = createSnapshot();

export function bootstrap() {
  const contracts: Partial<Contracts> = {};

  before(restoreSnapshot);

  before('load contracts', function () {
    Object.assign(contracts, {
      CoreRouter: getContract('CoreRouter'),
      CoreProxy: getContract('CoreProxy'),
      AccountProxy: getContract('AccountProxy'),
      DebtShareMock: getContract('DebtShareMock'),
      CouncilTokenRouter: getContract('CouncilTokenRouter'),
    } satisfies Contracts);
  });

  return {
    c: contracts as Contracts,
    getProvider,
    getSigners,
    getContract,
    createSnapshot,
  };
}
