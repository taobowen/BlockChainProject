import hre from "hardhat";

async function main() {
  const { ethers } = hre;

  const [deployer, provider, user] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const mock = await ethers.deployContract("MockStablecoin", ["Mock USD", "mUSD"]);
  await mock.waitForDeployment();
  const mockAddr = await mock.getAddress();

  const pass = await ethers.deployContract("AccessPass", [
    "SubScribe Access Pass",
    "SUBPASS",
    deployer.address,
  ]);
  await pass.waitForDeployment();
  const passAddr = await pass.getAddress();

  const grace = 3 * 24 * 60 * 60;
  const reminderWindow = 1 * 24 * 60 * 60;
  const manager = await ethers.deployContract("SubscriptionManager", [
    passAddr,
    grace,
    reminderWindow,
  ]);
  await manager.waitForDeployment();
  const managerAddr = await manager.getAddress();

  await (await pass.setManager(managerAddr)).wait();

  await (await manager.setAllowedToken(mockAddr, true)).wait();
  const price = ethers.parseUnits("10", 18);
  const duration = 30 * 24 * 60 * 60;
  await (await manager.createPlan(price, duration, mockAddr)).wait();

  await (await mock.mint(user.address, ethers.parseUnits("1000", 18))).wait();
  await (await mock.connect(user).approve(managerAddr, price)).wait();
  await (await manager.connect(user).subscribe(1)).wait();

  const nextId = await pass.nextId();
  const owner = await pass.ownerOf(nextId);
  const exp = await pass.expiresAt(nextId);

  console.log("\nDeployed addresses:");
  console.log("  MockStablecoin:", mockAddr);
  console.log("  AccessPass:", passAddr);
  console.log("  SubscriptionManager:", managerAddr);
  console.log(`Minted tokenId=${nextId.toString()} owner=${owner} expiresAt=${exp.toString()}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
