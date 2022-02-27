// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./IWind.sol";

abstract contract WindImplementationPointerUpgradeable is OwnableUpgradeable {
    IWind internal wind;

    event UpdateWind(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    modifier onlyWind() {
        require(
            address(wind) != address(0),
            "Implementations: Wind is not set"
        );
        address sender = _msgSender();
        require(
            sender == address(wind),
            "Implementations: Not Wind"
        );
        _;
    }

    function getWindImplementation() public view returns (address) {
        return address(wind);
    }

    function changeWindImplementation(address newImplementation)
        public
        virtual
        onlyOwner
    {
        address oldImplementation = address(wind);
        require(
            AddressUpgradeable.isContract(newImplementation) ||
                newImplementation == address(0),
            "Wind: You can only set 0x0 or a contract address as a new implementation"
        );
        wind = IWind(newImplementation);
        emit UpdateWind(oldImplementation, newImplementation);
    }

    uint256[49] private __gap;
}