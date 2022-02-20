const { ethers } = require("hardhat");

async function main() {
  const Hedron = await ethers.getContractFactory("Hedron");
  const hedron = await Hedron.deploy("0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39", 1575331200);
  await hedron.deployed()

  console.log("Hedron deployed to:", hedron.address);
  console.log("HSIM deployed to:", await hedron.hsim());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
