# BlockChainProject

# preparation

node version 22

# command

## Sanity-check the connection
npx hardhat console --network ganachegui
> (await ethers.provider.getBlockNumber()).toString()

## Deploy your contracts to the GUI chain
npx hardhat compile
npx hardhat run scripts/deploy.ts --network ganachegui

## function test
npx hardhat test
