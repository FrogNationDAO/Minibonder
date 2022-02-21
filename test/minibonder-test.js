const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Minibonder", function () {
    var deployer, bob, alice;
    var FRG, minibonder;
    const deployedContracts = {};

    async function deployContract(name, ...constructorArgs) {
        if (constructorArgs.length === 0) {
	        constructorArgs = null;
        }

        const Contract = await hre.ethers.getContractFactory(name);
        const contract = await Contract.deploy.apply(Contract, constructorArgs);

        return await contract
	        .deployed()
            .then(() => {
            console.log(`${name} deployed to:`, contract.address);
            deployedContracts[name] = contract.address;
            return contract;
        })
        .catch((err) => {
            console.log(arguments);
        });
    }

    async function mineBlocks(seconds) {
        await network.provider.send("evm_increaseTime", [seconds]);
        await network.provider.send("evm_mine")
    }

    before(async function () {
        let accounts = await ethers.getSigners();
        deployer = accounts[0];
        bob = accounts[1];

        let mintAmount = ethers.utils.parseUnits("1000000", 18);
        FRG = await deployContract(
            "Coin",
            "Frog Nation DAO",
            "FRG",
            mintAmount,
            deployer.address
        );

        let one_minute = 60;
        let ten_days = 864000;
        let vest_period = one_minute;
        let ftm_frg_pair = "0xedb14354733296B162775cBfB7032C3EC28A927E"
        let discount = 1000;
        minibonder = await deployContract(
            "Minibonder",
            FRG.address,
            ftm_frg_pair,
            vest_period,
            discount
        );
    });

    it("Should revert no value", async function () {
        await expect(minibonder.vest({ value: 0 })).to.be.revertedWith("Minibonder: More than 0 FTM required");
    });

    it("Should revert due to no reserve", async function () {
        let amountToVest = ethers.utils.parseUnits("1", 18);
        await expect(minibonder.vest({ value: amountToVest })).to.be.revertedWith("Minibonder: Reserve insufficient");
        await FRG.transfer(minibonder.address, ethers.utils.parseEther("1000000"));
    });

    it("Should successfully deposit", async function () {
        let amount = ethers.utils.parseUnits("1", 18);
        await minibonder.vest({ value: amount });
        let userVestedInfo = await minibonder.vestedBalances(deployer.address);
        let balanceVested = userVestedInfo.balance;

        let expectedAmount = await minibonder.approximateReward(amount);
        await expect(balanceVested).to.be.equal(expectedAmount.toString());
    });

    it("Should revert due to non-ownership of vest", async function () {
        await expect(minibonder.connect(bob).release()).to.be.revertedWith("Minibonder: Non vested");
    });

    it("Should revert due to vest locked", async function () {
        await expect(minibonder.release()).to.be.revertedWith("Minibonder: Release timestamp hasn't been reached");
    });

    it("Should succeed releasing from vest", async function () {
        let userEligible = await minibonder.vestedBalances(deployer.address);
        userEligible = userEligible[1];
        await mineBlocks(60);
        await minibonder.release();

        let userBalance = await FRG.balanceOf(deployer.address);

        await expect(userBalance).to.equal(userEligible);
    });

    it("Should do an FTM soft withdraw", async function () {
        await minibonder.withdrawFTM();
        let amount = ethers.utils.parseUnits("450", 18);

        expect(await ethers.provider.getBalance(minibonder.address)).to.equal(0);
    });

    it("Should do an emergency withdraw", async function () {
        await minibonder.emergencyWithdraw();
        expect(await FRG.balanceOf(minibonder.address)).to.equal(0);
        expect(await ethers.provider.getBalance(minibonder.address)).to.equal(0);
    });

    it("Should withdraw all FTM", async function () {
        let amount = ethers.utils.parseUnits("1000", 18);
        let tx = await deployer.sendTransaction({
            to: minibonder.address,
            value: amount
        });
        await minibonder.withdrawFTM();
        let remainingFTM = await ethers.provider.getBalance(minibonder.address);
        expect(remainingFTM).to.equal(0);
    });
});
