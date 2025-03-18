// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { AclAmmPoolFactory } from "../../../contracts/AclAmmPoolFactory.sol";
import { AclAmmPoolFactoryMock } from "../../../contracts/test/AclAmmPoolFactoryMock.sol";
/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "Acl Amm Pool". These
 * functions should have support for reusing artifacts from the hardhat compilation.
 */
contract AclAmmPoolContractsDeployer is BaseContractsDeployer {
    string private artifactsRootDir = "artifacts/";

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-aclamm/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-aclamm/";
        }
    }

    function deployAclAmmPoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (AclAmmPoolFactory) {
        if (reusingArtifacts) {
            return
                AclAmmPoolFactory(
                    deployCode(
                        _computeAclAmmPath(type(AclAmmPoolFactory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new AclAmmPoolFactory(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function deployAclAmmPoolFactoryMock(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (AclAmmPoolFactoryMock) {
        if (reusingArtifacts) {
            return
                AclAmmPoolFactoryMock(
                    deployCode(
                        _computeAclAmmTestPath(type(AclAmmPoolFactoryMock).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion)
                    )
                );
        } else {
            return new AclAmmPoolFactoryMock(vault, pauseWindowDuration, factoryVersion, poolVersion);
        }
    }

    function _computeAclAmmPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }

    function _computeAclAmmTestPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
