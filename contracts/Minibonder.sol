//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IUniswapV2Pair.sol";
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

    address public immutable pair;
    IERC20 public immutable vestedAsset;

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

    constructor(address _vestedAsset, address _pair, uint256 _vestPeriod, uint256 _vestDiscount) {
        require(_vestedAsset != address(0), "Minibonder: Vested asset cannot be zero address");
        vestedAsset = IERC20(_vestedAsset);
        pair = _pair;
        require(_vestPeriod > 0, "Minibonder: Vest period cannot be zero");
        vestPeriod = _vestPeriod;
        vestDiscount = _vestDiscount;
    }

    function vest() external payable whenNotPaused {
        _vest(msg.sender);
        emit Deposit(msg.sender, msg.value, vestPeriod);
    }

  /**
   * @dev Creates a vesting contract that vests balance of vestedAsset token to the
   * _vester.
   * @param vester address of the beneficiary to whom vested tokens are transferred
   */
    function _vest(
        address vester
    ) internal returns (uint256) {
        uint256 amountToVest = msg.value;
        require(amountToVest > 0, "Minibonder: More than 0 FTM required");

        uint256 miniBonderBalance = vestedAsset.balanceOf(address(this));
        uint256 amountToReturn = approximateReward(amountToVest);
        require(amountToReturn <= miniBonderBalance - totalEligible, "Minibonder: Reserve insufficient");

        if (vestedBalances[msg.sender].vester == address(0x0)) {
            UserVestedInfo memory vestedInfo;
            vestedInfo.vester = vester;
            vestedInfo.balance += amountToReturn;
            vestedInfo.releaseTimestamp = block.timestamp + vestPeriod;

            vestedBalances[msg.sender] = vestedInfo;
        } else {
            vestedBalances[msg.sender].balance += amountToVest;
            vestedBalances[msg.sender].releaseTimestamp = block.timestamp + vestPeriod;
        }

        totalEligible += amountToReturn;
        return vestedInfo.balance;
    }

  /**
   * @dev Approximates how much reward amount of vest gets
     @param amount Amount of potential vest to calculate reward for
   */
    function approximateReward(uint256 amount) public view returns (uint256) {
        uint256 amountPreDiscount = ((amount / 1e18) * getTokenPrice(amount));
        uint256 amountToReturn = amountPreDiscount - percentage(amountPreDiscount, vestDiscount);

        return amountToReturn;
    }

  /**
   * @dev Gets price using pair interface
   * @param amount Amount of vestedAsset to get price of
   */
    function getTokenPrice(uint256 amount) internal view returns(uint256) {
        IUniswapV2Pair swapPair = IUniswapV2Pair(pair);
        (uint256 Res0, uint256 Res1,) = swapPair.getReserves();

        uint res1 = Res1 * (10**18);
        return((amount*res1) / Res0 / 1e18);
    }

    receive() external payable {}

  /**
   * @dev Transfers vested tokens to vester.
   */
    function release() external whenNotPaused returns (bool) {
        require(vestedBalances[msg.sender].vester == msg.sender, "Minibonder: Non vested");
        require(vestedBalances[msg.sender].balance > 0, "Minibonder: Nothing vested");
        require(
            vestedBalances[msg.sender].releaseTimestamp <= block.timestamp,
            "Minibonder: Release timestamp hasn't been reached"
        );

        uint256 amountToReturn = vestedBalances[msg.sender].balance;
        totalEligible -= amountToReturn;
        vestedBalances[msg.sender].balance = 0;

        emit Withdraw(msg.sender, amountToReturn);
        require(vestedAsset.transfer(msg.sender, amountToReturn));
        return true;
    }

  /**
   * @dev Returns percentage of
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
    function withdrawFTM() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Minibonder: Contract holds no FTM");

        payable(msg.sender).transfer(contractBalance);
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
    function emergencyTokenWithdraw(address _token) external onlyOwner {
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

  /**
   * @dev Toggles whether contract paused
   */
    function togglePause() external onlyOwner {
        paused() == true ? _unpause() : _pause();
    }
}
