const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

// const MAX_BPS = 10000;
// const BID_BUFFER_BPS = 500;

module.exports = buildModule("marketplace", (m) => {

  const marketplace = m.contract("marketplace");

  return { marketplace };
});
//npx hardhat ignition deploy ./ignition/modules/marketplace.js --network localhost
