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
        console.log(deployer.address);


        let mintAmount = ethers.utils.parseUnits("10000", 18);
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
        let discount = 1000;
        minibonder = await deployContract(
            "Minibonder",
            FRG.address,
            vest_period,
            discount
        );
    });

    it("Should revert no value", async function () {
        await expect(minibonder.vest({ value: 0 })).to.be.revertedWith("Minibonder: More than 0 FTM required");
    });

    it("Should revert due to no reserve", async function () {
        let amount = ethers.utils.parseUnits("9000", 18);
        await expect(minibonder.vest({ value: amount })).to.be.revertedWith("Minibonder: Reserve insufficient");
        await FRG.transfer(minibonder.address, amount);
    });

    it("Should successfully deposit", async function () {
        let amount = ethers.utils.parseUnits("500", 18);
        await minibonder.vest({ value: amount });
        let userVestedInfo = await minibonder.vestedBalances(deployer.address);
        let balanceVested = userVestedInfo.balance;

        await expect(balanceVested).to.be.equal(amount.toString());
    });

    it("Should revert due to non-ownership of vest", async function () {
        await expect(minibonder.connect(bob).release()).to.be.revertedWith("Minibonder: Non vested");
    });

    it("Should revert due to vest locked", async function () {
        await expect(minibonder.release()).to.be.revertedWith("Minibonder: Release timestamp hasn't been reached");
    });

    it("Should succeed releasing from vest", async function () {
        let userTokenBalance = await FRG.balanceOf(deployer.address);
        await mineBlocks(60);
        await minibonder.release();
        userTokenBalance = await FRG.balanceOf(deployer.address);

        let amount = ethers.utils.parseUnits("1550", 18);
        let userBalance = await FRG.balanceOf(deployer.address);
        await expect(userBalance).to.equal(amount);

        //console.log(await FRG.balanceOf(minibonder.address));
        //console.log(await ethers.provider.getBalance(deployer.address));
    });

    it("Should do an FTM soft withdraw", async function () {
        await minibonder.softWithdrawFTM();
        let amount = ethers.utils.parseUnits("450", 18);

        expect(await ethers.provider.getBalance(minibonder.address)).to.equal(amount);
    });

    it("Should do an FRG soft withdraw", async function () {
        let amount = ethers.utils.parseUnits("100", 18);
        await minibonder.vest({ value: amount });
        let userVestedInfo = await minibonder.vestedBalances(deployer.address);
        let balanceVested = userVestedInfo.balance;

        await minibonder.softWithdrawVestedAsset();
        amount = ethers.utils.parseUnits("110", 18);
        expect(await FRG.balanceOf(minibonder.address)).to.equal(amount);
    });

    it("Should do an emergency withdraw", async function () {
        await minibonder.emergencyWithdraw();
        expect(await FRG.balanceOf(minibonder.address)).to.equal(0);
        expect(await ethers.provider.getBalance(minibonder.address)).to.equal(0);
    });

});
