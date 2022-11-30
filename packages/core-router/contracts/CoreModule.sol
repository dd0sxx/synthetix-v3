//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnerModule} from "@synthetixio/core-modules/contracts/modules/OwnerModule.sol";
import {UpgradeModule} from "@synthetixio/core-modules/contracts/modules/UpgradeModule.sol";

// solhint-disable-next-line no-empty-blocks
contract CoreModule is OwnerModule, UpgradeModule {

}