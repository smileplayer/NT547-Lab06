// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 25520343. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract StakingPool_0343 {
    address public owner;
    mapping(address => uint256) public ledger;
    IERC20Like public stableCoin;
    mapping(address => uint256) public points;
    address payable internal beneficiary;
    uint256 public cooldownEnd;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        beneficiary = payable(msg.sender);
    }

    function fund() external payable {
        ledger[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function dayOfWeek() external view returns (uint256) {
        // slither-disable-next-line weak-prng
        return (block.timestamp / 1 days + 4) % 7;
    }

    function setRewardToken(address t) external onlyOwner {
        require(t != address(0), "zero");
        stableCoin = IERC20Like(t);
    }

    function convertRewards(uint256 amount) external {
        require(points[msg.sender] >= amount, "not enough");
        points[msg.sender] -= amount;
        require(stableCoin.transfer(msg.sender, amount), "transfer failed");
    }

    function moveToTreasury() external onlyOwner {
        require(beneficiary != address(0), "no beneficiary");
        beneficiary.transfer(address(this).balance / 2);
    }

    function exitPool() external {
        uint256 amount = ledger[msg.sender];
        require(amount > 0, "empty");
        ledger[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "send failed");
    }

    function updateOwner(address newOwner) external {
        require(tx.origin == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function releaseTenth() external onlyOwner {
        require(block.timestamp >= cooldownEnd, "locked");
        cooldownEnd = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }
}
