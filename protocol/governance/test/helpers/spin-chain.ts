import path from 'node:path';
import { cannonBuild, cannonInspect } from '@synthetixio/core-modules/test/helpers/cannon';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { glob, runTypeChain } from 'typechain';

import type { CcipRouterMock } from '../generated/typechain/sepolia';
import type { SnapshotRecordMock } from '../generated/typechain/sepolia';

export async function spinChain<CoreProxy>({
  networkName,
  cannonfile,
  writeDeployments,
  typechainFolder,
  chainSlector,
  ownerAddress = '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266',
}: {
  networkName: string;
  cannonfile: string;
  writeDeployments: string;
  typechainFolder: string;
  chainSlector: string;
  ownerAddress?: string;
}) {
  if (!hre.config.networks[networkName]) {
    throw new Error(`Invalid network "${networkName}"`);
  }

  const { chainId } = hre.config.networks[networkName];

  if (typeof chainId !== 'number') {
    throw new Error(`Invalid chainId on network ${networkName}`);
  }

  writeDeployments = path.join(writeDeployments, networkName);
  typechainFolder = path.join(typechainFolder, networkName);

  console.log(`  Building: ${cannonfile} - Network: ${networkName}`);

  const { packageRef, provider, outputs } = await cannonBuild({
    cannonfile: path.join(hre.config.paths.root, cannonfile),
    chainId,
    impersonate: ownerAddress,
    wipe: true,
    getArtifact: async (contractName: string) =>
      await hre.run('cannon:get-artifact', { name: contractName }),
    pkgInfo: require(path.join(hre.config.paths.root, 'package.json')),
    projectDirectory: hre.config.paths.root,
  });

  await cannonInspect({
    chainId,
    packageRef,
    writeDeployments,
  });

  const allFiles = glob(hre.config.paths.root, [`${writeDeployments}/**/*.json`]);

  await runTypeChain({
    cwd: hre.config.paths.root,
    filesToProcess: allFiles,
    allFiles,
    target: 'ethers-v5',
    outDir: typechainFolder,
  });

  const signer = provider.getSigner(ownerAddress);

  const CoreProxy = new ethers.Contract(
    outputs.contracts!.CoreProxy.address,
    outputs.contracts!.CoreProxy.abi,
    signer
  ) as CoreProxy;

  const SnapshotRecordMock = new ethers.Contract(
    outputs.contracts!.SnapshotRecordMock.address,
    outputs.contracts!.SnapshotRecordMock.abi,
    signer
  ) as SnapshotRecordMock;

  const CcipRouter = new ethers.Contract(
    outputs.contracts!.CcipRouterMock.address,
    outputs.contracts!.CcipRouterMock.abi,
    signer
  ) as CcipRouterMock;

  return {
    networkName,
    chainId,
    chainSlector,
    provider: provider as unknown as ethers.providers.JsonRpcProvider,
    CoreProxy,
    CcipRouter,
    signer,
    SnapshotRecordMock,
  };
}
