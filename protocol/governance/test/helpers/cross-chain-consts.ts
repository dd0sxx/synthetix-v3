import {ethers} from "ethers";

// rpc
export const OPTIMISM_HOST = "http://localhost:8545";
export const ETH_HOST = "http://localhost:8546";

// forks
// export const FORK_OPTIMISM_CHAIN_ID = Number(
//   process.env.TESTING_OPTIMISM_FORK_CHAINID!
// );
// export const FORK_ETH_CHAIN_ID = Number(process.env.TESTING_ETH_FORK_CHAINID!);

// // Avalanche wormhole variables
// export const OPTIMISM_WORMHOLE_ADDRESS = process.env.TESTING_OPTIMISM_WORMHOLE_ADDRESS!;
// export const OPTIMISM_WORMHOLE_CHAIN_ID = Number(
//   process.env.TESTING_OPTIMISM_WORMHOLE_CHAINID!
// );
// export const OPTIMISM_WORMHOLE_MESSAGE_FEE = ethers.BigNumber.from(
//   process.env.TESTING_OPTIMISM_WORMHOLE_MESSAGE_FEE!
// );
// export const OPTIMISM_WORMHOLE_GUARDIAN_SET_INDEX = Number(
//   process.env.TESTING_OPTIMISM_WORMHOLE_GUARDIAN_SET_INDEX!
// );
// export const OPTIMISM_BRIDGE_ADDRESS = process.env.TESTING_OPTIMISM_BRIDGE_ADDRESS!;

// // Ethereum wormhole variables
// export const ETH_WORMHOLE_ADDRESS = process.env.TESTING_ETH_WORMHOLE_ADDRESS!;
// export const ETH_WORMHOLE_CHAIN_ID = Number(
//   process.env.TESTING_ETH_WORMHOLE_CHAINID!
// );
// export const ETH_WORMHOLE_MESSAGE_FEE = ethers.BigNumber.from(
//   process.env.TESTING_ETH_WORMHOLE_MESSAGE_FEE!
// );
// export const ETH_WORMHOLE_GUARDIAN_SET_INDEX = Number(
//   process.env.TESTING_ETH_WORMHOLE_GUARDIAN_SET_INDEX!
// );
// export const ETH_BRIDGE_ADDRESS = process.env.TESTING_ETH_BRIDGE_ADDRESS!;

// // signer
// export const GUARDIAN_PRIVATE_KEY = process.env.TESTING_DEVNET_GUARDIAN!;
// export const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY!;
// export const WALLET_PRIVATE_KEY_TWO = process.env.WALLET_PRIVATE_KEY_TWO!;

// wormhole event ABIs
export const WORMHOLE_TOPIC =
  "0x6eb224fb001ed210e379b335e35efe88672a8ce935d981a6896b27ffdf52a3b2";
export const WORMHOLE_MESSAGE_EVENT_ABI = [
  "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)",
];