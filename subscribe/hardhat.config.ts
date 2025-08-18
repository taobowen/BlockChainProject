import "@nomicfoundation/hardhat-toolbox";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
dotenv.config();

import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    ganachegui: {
      url: process.env.GANACHE_URL || "http://127.0.0.1:7545",
      chainId: Number(process.env.GANACHE_CHAIN_ID || 5777),
      // EITHER mnemonic (multiple accounts) ...
      accounts: process.env.GANACHE_MNEMONIC
        ? { mnemonic: process.env.GANACHE_MNEMONIC, count: 10 }
        // ... OR a single private key:
        : process.env.GANACHE_PRIVATE_KEY
        ? [process.env.GANACHE_PRIVATE_KEY]
        : [],
    },
  },
  typechain: { outDir: "typechain-types", target: "ethers-v6" },
};
export default config;
