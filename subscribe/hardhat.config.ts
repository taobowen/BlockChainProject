import "@nomicfoundation/hardhat-toolbox";
import "@typechain/hardhat";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
  networks: {
    ganache: {
      url: process.env.GANACHE_URL || "http://127.0.0.1:8545",
      chainId: Number(process.env.GANACHE_CHAIN_ID || 1337),
      // Use one of the printed Ganache private keys
      accounts: process.env.GANACHE_PRIVATE_KEY ? [process.env.GANACHE_PRIVATE_KEY] : []
    },
    // keep "hardhat" network too (default)
  },
};

export default config;
