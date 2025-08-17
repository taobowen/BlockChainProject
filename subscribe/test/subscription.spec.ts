import { expect } from "chai";
import hre from "hardhat";

describe("SubscriptionManager", () => {
  it("happy path", async () => {
    const { ethers } = hre;
    const [deployer, user] = await ethers.getSigners();

    const mock = await ethers.deployContract("MockStablecoin", ["Mock USD", "mUSD"]);
    await mock.waitForDeployment();
    const mockAddr = await mock.getAddress();

    const pass = await ethers.deployContract("AccessPass", ["SubScribe Access Pass", "SUBPASS", deployer.address]);
    await pass.waitForDeployment();

    const manager = await ethers.deployContract("SubscriptionManager", [await pass.getAddress(), 0, 0]);
    await manager.waitForDeployment();

    await (await pass.setManager(await manager.getAddress())).wait();

    await (await manager.setAllowedToken(mockAddr, true)).wait();
    const price = ethers.parseUnits("10", 18);
    const duration = 30 * 24 * 60 * 60;
    await (await manager.createPlan(price, duration, mockAddr)).wait();

    await (await mock.mint(user.address, ethers.parseUnits("1000", 18))).wait();
    await (await mock.connect(user).approve(await manager.getAddress(), price)).wait();
    await (await manager.connect(user).subscribe(1)).wait();

    const tokenId = await pass.nextId();
    expect(tokenId).to.equal(1n);
    expect(await pass.ownerOf(1)).to.equal(user.address);
    expect(await manager.isActive(1)).to.equal(true);
  });
});
