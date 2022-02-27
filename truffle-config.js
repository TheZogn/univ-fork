const HDWalletProvider = require("@truffle/hdwallet-provider");
require('dotenv').config();

const privateKey = process.env.PRIVATE_KEY
const snowtraceKey = process.env.SNOWTRACE_KEY

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // for more about customizing your Truffle configuration!
  plugins: ['truffle-plugin-verify'], // for etherscan/snowtrace verification
  compilers: {
    solc: {
      version: "^0.8.11",    // Fetch exact version from solc-bin (default: truffle's version)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 1
        },
      }
      //  evmVersion: "byzantium"
      // }
    }
  },
  networks: {
    development: {
      host: '172.21.32.1', // WSL RPC provider
      port: 7545,
      network_id: '*', // Match any network id
    },
    fuji: {
      network_id: 43113,
      provider: function() {
        return new HDWalletProvider({
          privateKeys:[privateKey],
          providerOrUrl: "https://api.avax-test.network/ext/bc/C/rpc"
        })
      }
    },
  },
  api_keys: {
    snowtrace: snowtraceKey
  }
};
