//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@synthetixio/core-contracts/contracts/token/ERC721Enumerable.sol";
import "@synthetixio/core-contracts/contracts/utils/AddressUtil.sol";
import "@synthetixio/core-contracts/contracts/initializable/InitializableMixin.sol";
import "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import "@synthetixio/core-contracts/contracts/errors/AddressError.sol";

import "../storage/Initialized.sol";

import "../interfaces/INftModule.sol";

contract NftModule is INftModule, ERC721Enumerable, InitializableMixin {
    bytes32 internal constant _INITIALIZED_NAME = "NftModule";

    function _isInitialized() internal view override returns (bool) {
        return Initialized.load(_INITIALIZED_NAME).initialized;
    }

    function isInitialized() external view returns (bool) {
        return _isInitialized();
    }

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        string memory uri
    ) public {
        OwnableStorage.onlyOwner();

        _initialize(tokenName, tokenSymbol, uri);
        Initialized.load(_INITIALIZED_NAME).initialized = true;
    }
}