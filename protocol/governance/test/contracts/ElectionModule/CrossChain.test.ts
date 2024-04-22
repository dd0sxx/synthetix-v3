import {ethers} from "ethers";
import { bootstrap } from '../../bootstrap';
import {
    OPTIMISM_HOST,
    OPTIMISM_WORMHOLE_ADDRESS,
    WALLET_PRIVATE_KEY,
    OPTIMISM_WORMHOLE_GUARDIAN_SET_INDEX,
    GUARDIAN_PRIVATE_KEY,
    FORK_OPTIMISM_CHAIN_ID,
    ETH_HOST,
    ETH_WORMHOLE_ADDRESS,
    FORK_ETH_CHAIN_ID,
  } from "../../helpers/cross-chain-consts";


describe.only("Sends Crosschain Message", () => {
    const { c, getSigners, getProvider, snapshotCheckpoint } = bootstrap();

    let owner: ethers.Signer;
    let user: ethers.Signer;
    let ElectionModule: GovernanceProxy;

});
//   // optimism wallet
//   const optimismProvider = new ethers.providers.StaticJsonRpcProvider(OPTIMISM_HOST);
//   const optimismWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, optimismProvider);

//   // eth wallet
//   const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_HOST);
//   const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);

//   // wormhole contract
//   const optimismWormhole = IWormhole__factory.connect(
//     OPTIMISM_WORMHOLE_ADDRESS,
//     optimismWallet
//   );
//   const ethWormhole = IWormhole__factory.connect(
//     ETH_WORMHOLE_ADDRESS,
//     ethWallet
//   );

//   // HelloWorld contract
//   const optimismHelloWorld = HelloWorld__factory.connect(
//     readHelloWorldContractAddress(FORK_OPTIMISM_CHAIN_ID),
//     optimismWallet
//   );
//   const ethHelloWorld = HelloWorld__factory.connect(
//     readHelloWorldContractAddress(FORK_ETH_CHAIN_ID),
//     ethWallet
//   );

//   describe("Test Contract Deployment and Emitter Registration", () => {
//     it("Verify OPTIMISM Contract Deployment", async () => {
//       // confirm chainId
//       const deployedChainId = await optimismHelloWorld.chainId();
//       expect(deployedChainId).to.equal(CHAIN_ID_OPTIMISM);
//     });

//     it("Verify ETH Contract Deployment", async () => {
//       // confirm chainId
//       const deployedChainId = await ethHelloWorld.chainId();
//       expect(deployedChainId).to.equal(CHAIN_ID_ETH);
//     });

//     it("Should Register HelloWorld Contract Emitter on OPTIMISM", async () => {
//       // Convert the target contract address to bytes32, since other
//       // non-evm blockchains (e.g. Solana) have 32 byte wallet addresses.
//       const targetContractAddressHex =
//         "0x" + tryNativeToHexString(ethHelloWorld.address, CHAIN_ID_ETH);

//       // register the emitter
//       const receipt = await optimismHelloWorld
//         .registerEmitter(CHAIN_ID_ETH, targetContractAddressHex)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // query the contract and confirm that the emitter is set in storage
//       const emitterInContractState = await optimismHelloWorld.getRegisteredEmitter(
//         CHAIN_ID_ETH
//       );
//       expect(emitterInContractState).to.equal(targetContractAddressHex);
//     });

//     it("Should Register HelloWorld Contract Emitter on ETH", async () => {
//       // Convert the target contract address to bytes32, since other
//       // non-evm blockchains (e.g. Solana) have 32 byte wallet addresses.
//       const targetContractAddressHex =
//         "0x" + tryNativeToHexString(optimismHelloWorld.address, CHAIN_ID_OPTIMISM);

//       // register the emitter
//       const receipt = await ethHelloWorld
//         .registerEmitter(CHAIN_ID_OPTIMISM, targetContractAddressHex)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // query the contract and confirm that the emitter is set in storage
//       const emitterInContractState = await ethHelloWorld.getRegisteredEmitter(
//         CHAIN_ID_OPTIMISM
//       );
//       expect(emitterInContractState).to.equal(targetContractAddressHex);
//     });
//   });

//   describe("Test HelloWorld Interface", () => {
//     // simulated guardian that signs wormhole messages
//     const guardians = new MockGuardians(OPTIMISM_WORMHOLE_GUARDIAN_SET_INDEX, [
//       GUARDIAN_PRIVATE_KEY,
//     ]);

//     let localVariables: any = {};

//     it("Should Send HelloWorld Message From OPTIMISM", async () => {
//       // HelloWorld message to send
//       localVariables.helloWorldMessage = "HelloEthereum";

//       // invoke the HelloWorld contract to emit the HelloWorld wormhole message
//       const receipt = await optimismHelloWorld
//         .sendMessage(localVariables.helloWorldMessage)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // simulate signing the VAA with the mock guardian
//       const unsignedMessages = await formatWormholeMessageFromReceipt(
//         receipt!,
//         CHAIN_ID_OPTIMISM
//       );
//       expect(unsignedMessages.length).to.equal(1);

//       localVariables.signedHelloWorldMessage = guardians.addSignatures(
//         unsignedMessages[0],
//         [0]
//       );
//     });

//     it("Should Receive HelloWorld Message on ETH", async () => {
//       // invoke the receiveMessage on the ETH contract
//       const receipt = await ethHelloWorld
//         .receiveMessage(localVariables.signedHelloWorldMessage)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // parse the verified message by calling the wormhole core endpoint `parseVM`.
//       const parsedVerifiedMessage = await ethWormhole.parseVM(
//         localVariables.signedHelloWorldMessage
//       );

//       // Query the contract using the verified message's hash to confirm
//       // that the correct payload was saved in storage.
//       const storedMessage = await ethHelloWorld.getReceivedMessage(
//         parsedVerifiedMessage.hash
//       );
//       expect(storedMessage).to.equal(localVariables.helloWorldMessage);

//       // confirm that the contract marked the message as "consumed"
//       const isMessageConsumed = await ethHelloWorld.isMessageConsumed(
//         parsedVerifiedMessage.hash
//       );
//       expect(isMessageConsumed).to.be.true;

//       // clear localVariables
//       localVariables = {};
//     });

//     it("Should Send HelloWorld Message From ETH", async () => {
//       // HelloWorld message to send
//       localVariables.helloWorldMessage = "HelloAvalanche";

//       // invoke the HelloWorld contract to emit the HelloWorld wormhole message
//       const receipt = await ethHelloWorld
//         .sendMessage(localVariables.helloWorldMessage)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // simulate signing the VAA with the mock guardian
//       const unsignedMessages = await formatWormholeMessageFromReceipt(
//         receipt!,
//         CHAIN_ID_ETH
//       );
//       expect(unsignedMessages.length).to.equal(1);

//       localVariables.signedHelloWorldMessage = guardians.addSignatures(
//         unsignedMessages[0],
//         [0]
//       );
//     });

//     it("Should Receive HelloWorld Message on OPTIMISM", async () => {
//       // invoke the receiveMessage on the OPTIMISM
//       const receipt = await optimismHelloWorld
//         .receiveMessage(localVariables.signedHelloWorldMessage)
//         .then((tx: ethers.ContractTransaction) => tx.wait())
//         .catch((msg: any) => {
//           // should not happen
//           console.log(msg);
//           return null;
//         });
//       expect(receipt).is.not.null;

//       // parse the verified message by calling the wormhole core endpoint `parseVM`.
//       const parsedVerifiedMessage = await optimismWormhole.parseVM(
//         localVariables.signedHelloWorldMessage
//       );

//       // Query the contract using the verified message's hash to confirm
//       // that the correct payload was saved in storage.
//       const storedMessage = await optimismHelloWorld.getReceivedMessage(
//         parsedVerifiedMessage.hash
//       );
//       expect(storedMessage).to.equal(localVariables.helloWorldMessage);

//       // confirm that the contract marked the message as "consumed"
//       const isMessageConsumed = await optimismHelloWorld.isMessageConsumed(
//         parsedVerifiedMessage.hash
//       );
//       expect(isMessageConsumed).to.be.true;
//     });

//     it("Should Only Receive Signed Message Once", async () => {
//       try {
//         // invoke the receiveMessage again and confirm that it fails
//         await optimismHelloWorld
//           .receiveMessage(localVariables.signedHelloWorldMessage)
//           .then((tx: ethers.ContractTransaction) => tx.wait());
//       } catch (error: any) {
//         expect(error.error.reason).to.equal(
//           "execution reverted: message already consumed"
//         );
//       }

//       // clear localVariables
//       localVariables = {};
//     });
//   });
// });