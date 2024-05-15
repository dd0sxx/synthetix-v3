// import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
// import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
// import assert from 'assert';
// import { ethers } from 'ethers';
// import { ElectionPeriod } from '../constants';
// import { typedEntries, typedValues } from '../helpers/object';
// import { ChainSelector, WormholeRelayers, integrationBootstrap, SignerOnChains } from './bootstrap';

// describe('cross chain election testing', function () {
//   const { chains, fixtureSignerOnChains, fastForwardChainsTo } = integrationBootstrap();

//   let nominee: SignerOnChains;
//   let voter: SignerOnChains;

//   before('set up users', async function () {
//     nominee = await fixtureSignerOnChains();
//     voter = await fixtureSignerOnChains();
//   });

//   describe('sends message cross chain', function () {
//     it.only('cast will fail if not in voting period', async function () {
//         let ABI = ["emitCrossChainMessage(string memory message)"];
//         let iface = new ethers.utils.Interface(ABI);
//         let fullMessage = iface.encodeFunctionData("emitCrossChainMessage", ["hello wormhole!"]);
//         // await chains.satellite1.GovernanceProxy.connect(voter.satellite1).transmit(WormholeRelayers.satellite1, fullMessage);
//     });
//   });
// });