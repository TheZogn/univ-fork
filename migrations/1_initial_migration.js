const Migrations = artifacts.require("TurbinesManagerUpgradeable");

module.exports = function (deployer) {
  deployer.deploy(Migrations);
};
