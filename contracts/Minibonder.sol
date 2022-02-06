//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Minibonder
 * @dev A minibonder contract that permits the vesting of FRG in return for FTM
 * a an optional discount.
 */
contract Minibonder is Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public vestedAsset;
    uint256 public totalVested;
    uint256 public totalEligible;
    uint256 public vestPeriod;
    uint256 public vestDiscount;

    struct UserVestedInfo {
        address vester;
        uint256 balance;
        uint256 releaseTimestamp;
    }

    mapping(address => UserVestedInfo) public vestedBalances;

    event Deposit(address vester, uint256 amount, uint256 releaseTimestamp);
    event Withdraw(address vester, uint256 amount);
    event SettingsChanged(uint256 vestPeriod, uint256 vestDiscount);

    constructor(address _vestedAsset, uint256 _vestPeriod, uint256 _vestDiscount) {
        require(_vestedAsset != address(0), "Minibonder: Vested asset cannot be zero address");
        vestedAsset = IERC20(_vestedAsset);
        require(_vestPeriod > 0, "Minibonder: Vest period cannot be zero");
        vestPeriod = _vestPeriod;
        vestDiscount = _vestDiscount;
    }

    function vest() external payable whenNotPaused {
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

        UserVestedInfo memory vestedInfo;
        vestedInfo.vester = vester;
        vestedInfo.balance += amountToVest;
        vestedInfo.releaseTimestamp = block.timestamp + vestPeriod;

        vestedBalances[msg.sender] = vestedInfo;
        totalVested += amountToVest;

        uint256 amountToReturn = percentage(vestedBalances[msg.sender].balance, vestDiscount);
        amountToReturn = vestedBalances[msg.sender].balance + amountToReturn;
        totalEligible += amountToReturn;
        return true;
    }

    receive() external payable {}

  /**
   * @notice Transfers vested tokens to vester.
   */
    function release() external whenNotPaused returns (bool) {
        require(vestedBalances[msg.sender].vester == msg.sender, "Minibonder: Non vested");
        require(
            vestedBalances[msg.sender].releaseTimestamp <= block.timestamp,
            "Minibonder: Release timestamp hasn't been reached"
        );

        totalVested -= vestedBalances[msg.sender].balance;
        uint256 amountToReturn = percentage(vestedBalances[msg.sender].balance, vestDiscount);
        amountToReturn = vestedBalances[msg.sender].balance + amountToReturn;
        totalEligible -= amountToReturn;
        vestedBalances[msg.sender].balance = 0;

        emit Withdraw(msg.sender, amountToReturn);
        require(vestedAsset.transfer(msg.sender, amountToReturn));

        return true;
    }

  /**
   * @dev Calculates the amount that has already vested but hasn't been released yet.
   * @param number Number to derive percentage from
   * @param basisPoints perc in basisPoints
   */
    function percentage(uint256 number, uint256 basisPoints) internal pure returns (uint256) {
        return number * basisPoints / 10000;
    }

  /**
   * @dev Sends FTM to another address in case of an emergency
   * Takes into account vested FTM and ignores it
   */
    function softWithdrawFTM() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Minibonder: Contract holds no FTM");

        payable(msg.sender).transfer(contractBalance - totalVested);
    }

  /**
   * @dev Sends vestedAsset to another address in case of an emergency
   * Takes into account totalEligible and ignores it
   */
    function softWithdrawVestedAsset() external onlyOwner {
        uint256 contractTokenBalance = vestedAsset.balanceOf(address(this));
        require(contractTokenBalance > 0, "Minibonder: Contract holds no underlying asset");

        vestedAsset.transfer(msg.sender, contractTokenBalance - totalEligible);
    }

  /**
   * @dev Sends FTM and vestedAsset to another address in case of an emergency
   */
    function emergencyWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        uint256 contractTokenBalance = vestedAsset.balanceOf(address(this));
        if (contractTokenBalance > 0) vestedAsset.transfer(msg.sender, contractTokenBalance);
        if (contractBalance > 0) payable(msg.sender).transfer(contractBalance);
    }

  /**
   * @dev Sends unknown tokens to another address in case of an emergency
   */
    function emergencyThirdTokenWithdraw(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 contractTokenBalance = token.balanceOf(address(this));
        if (contractTokenBalance > 0) token.transfer(msg.sender, contractTokenBalance);
    }

  /**
   * @dev Allows modifying vestingPeriod and vestDiscount
   * @param _vestPeriod Desired vestPeriod in seconds
   * @param _vestDiscount Desired bonus percentage
   */
    function setBondSettings(uint256 _vestPeriod, uint256 _vestDiscount) external onlyOwner {
        vestPeriod = _vestPeriod == 1 ? vestPeriod : _vestPeriod;
        vestDiscount = _vestDiscount == 1 ? vestDiscount : _vestDiscount;
        emit SettingsChanged(vestPeriod, vestDiscount);
    }
}
