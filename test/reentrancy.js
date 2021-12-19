const { expect } = require("chai");

describe("Reentrancy Attack", function() {
  it("steal crv", async function() {
    const StealCrv = await ethers.getContractFactory("StealCrv");
    const stealCrv = await StealCrv.deploy();
    await stealCrv.deployed();
    console.log("deployed!")
    const triggerSell = await stealCrv.triggerSell();
    
    // wait until the transaction is mined
    await triggerSell.wait();
  });
});
