//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Minibonder
 * @dev A minibonder contract that permits the vesting of FRG in return for FTM
 * a an optional discount.
 */
contract Minibonder is Ownable {

    IERC20 public vestedAsset;
    uint256 public totalVested;
    uint256 public vestPeriod;
    uint256 public vestDiscount;

    struct userVestedInfo {
        address vester;
        uint256 balance;
        uint256 releaseTimestamp;
    }

    mapping(address => userVestedInfo) public vestedBalances;

    event Deposit(address vester, uint256 amount, uint256 releaseTimestamp);
    event Withdraw(address vester, uint256 amount);

    constructor(address _vestedAsset, uint256 _vestPeriod, uint256 _vestDiscount) {
        require(_vestedAsset != address(0), "Minibonder: Vested asset cannot be zero address");
        vestedAsset = IERC20(_vestedAsset);
        require(_vestPeriod > 0, "Minibonder: Vest period cannot be zero");
        vestPeriod = _vestPeriod;
        vestDiscount = _vestDiscount;
    }

    function vest(
    ) external payable {
        _vest(msg.sender);
        emit Deposit(msg.sender, msg.value, vestPeriod);
    }

  /**
   * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
   * _vester.
   * @param vester address of the beneficiary to whom vested tokens are transferred
   */
    function _vest(
        address vester
    ) internal returns (bool) {
        uint256 amountToVest = msg.value;
        uint256 miniBonderBalance = vestedAsset.balanceOf(address(this));
        require(amountToVest > 0, "Minibonder: More than 0 FTM required");
        require(amountToVest <= miniBonderBalance, "Minibonder: Reserve insufficient");

        userVestedInfo memory vestedInfo;
        vestedInfo.vester = vester;
        vestedInfo.balance += amountToVest;
        vestedInfo.releaseTimestamp = block.timestamp + vestPeriod;

        vestedBalances[msg.sender] = vestedInfo;
        totalVested += amountToVest;
        return true;
    }

  /**
   * @notice Transfers vested tokens to vester.
   */
    function release() external returns (bool) {
        require(vestedBalances[msg.sender].vester == msg.sender, "Minibonder: Non vested");
        require(vestedBalances[msg.sender].releaseTimestamp <= block.timestamp, "Minibonder: Release timestamp hasn't been reached");

        uint256 amountToReturn = percentage(vestedBalances[msg.sender].balance, vestDiscount);
        amountToReturn = vestedBalances[msg.sender].balance + amountToReturn;
        vestedBalances[msg.sender].balance = 0;

        require(vestedAsset.transfer(msg.sender, amountToReturn));
        emit Withdraw(msg.sender, amountToReturn);

        totalVested -= amountToReturn;
        return true;
    }

  /**
   * @dev Calculates the amount that has already vested but hasn't been released yet.
   * @param number Number to derive percentage from
   * @param basisPoints perc in basisPoints (preferably 10000ths)
   */
    function percentage(uint256 number, uint256 basisPoints) internal pure returns (uint256) {
        return number * basisPoints / 10000;
    }

  /**
   * @dev Sends the FTM to another address in case of an emergency
   * Takes into account vested FTM and ignores it
   */
    function softWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        payable(msg.sender).transfer(contractBalance - totalVested);
    }

  /**
   * @dev Sends the FTM to another address in case of an emergency
   */
    function emergencyWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        payable(msg.sender).transfer(contractBalance);

    }
}
