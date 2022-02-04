const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Hedron", function () {

  let hex;
  let hedron;
  let hsim;
  let hsi;
  let addr1;
  let addr2;

  before(async function () {
    Hex = await ethers.getContractFactory("contracts/references/HEX.sol:HEX");
    [addr1, addr2] = await ethers.getSigners();
  
    hex = await Hex.deploy();
    await hex.deployed();
  
    // move to HEX launch day (2019-12-03)
    await network.provider.send("evm_mine", [1575331200]);
  
    // enter the HEX adoption amplifier
    await hex.connect(addr1).xfLobbyEnter(addr2.address, {
      value: ethers.utils.parseEther("1.0")
    });
  
    // move two HEX days (2019-12-05)
    await network.provider.send("evm_mine", [1575500400]);
  
    // exit the HEX adoption amplifier, addr1 and addr2 should now have HEX tokens
    await hex.connect(addr1).xfLobbyExit(0,0);

    // create a hex stake of 100 HEX for 1 day for address 1
    await hex.connect(addr1).stakeStart(10000000000, 1);

    // create a hex stake of 100 HEX for 5555 days for address 2
    await hex.connect(addr2).stakeStart(10000000000, 5555);
  });

  it("Should not proccess transactions until launch day.", async function () {
    const Hedron = await ethers.getContractFactory("Hedron");
    hedron = await Hedron.deploy(hex.address, 1575331200);
    await hedron.deployed();

    await expect(hedron.mintInstanced(0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.mintNative(0, 0)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.calcLoanPayment(addr1.address, 0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.calcLoanPayoff(addr1.address, 0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.loanInstanced(0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.loanPayment(0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.loanPayoff(0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    await expect(hedron.loanLiquidate(addr1.address, 0, addr1.address)
    ).to.be.revertedWith("HDRN: Contract not yet active");

    // move to Hedron launch day
    await network.provider.send("evm_mine", [1645830000]);
  });

  it("Should pass native HEX stake minting sanity checks.", async function () {
    const stake1 = await hex.stakeLists(addr1.address, 0);

    // test invalid stakeId
    await expect(hedron.connect(addr1).mintNative(0, 0)
    ).to.be.revertedWith("HDRN: HEX stake index id mismatch");

    // create a second HEX stake of 100 HEX for 10 days for address 1
    await hex.connect(addr1).stakeStart(10000000000000, 10);
    const stake2 = await hex.stakeLists(addr1.address, 1);

    // create a third HEX stake of 100 HEX for 1 day for address 1
    await hex.connect(addr1).stakeStart(10000000000000, 1);
    const stake3 = await hex.stakeLists(addr1.address, 2);

    // create a fourth HEX stake of 100 HEX for 1 day for address 1
    await hex.connect(addr1).stakeStart(10000000000000, 1);
    const stake4 = await hex.stakeLists(addr1.address, 3);
    
    // test pending HEX stake
    await expect(hedron.connect(addr1).mintNative(1, stake2.stakeId)
    ).to.be.revertedWith("HDRN: cannot mint against a pending HEX stake");

    // claim should still work
    await hedron.connect(addr1).claimNative(1, stake2.stakeId);

    // test first stake one served day
    await hedron.connect(addr1).mintNative(0, stake1.stakeId);

    addr1Balance = await hedron.balanceOf(addr1.address);
    addr1ExpectedBalance = ethers.BigNumber.from(stake1.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake1.stakeShares.mul(100).div(10));

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test second stake zero served days
    await hedron.connect(addr1).mintNative(1, stake2.stakeId);
    
    addr1Balance = await hedron.balanceOf(addr1.address);

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test second stake one served day
    await hedron.connect(addr1).mintNative(1, stake2.stakeId);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake2.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake2.stakeShares.mul(100).div(10));

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test second stake two served days
    await hedron.connect(addr1).mintNative(1, stake2.stakeId);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake2.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake2.stakeShares.mul(100).div(10));

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next LPB bracket
    await network.provider.send("evm_increaseTime", [604800])
    await ethers.provider.send('evm_mine');

    // test third stake normal mint
    await hedron.connect(addr1).mintNative(2, stake3.stakeId);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares.mul(90).div(10));

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // test fourth stake claim then mint
    await hedron.connect(addr1).claimNative(3, stake4.stakeId);
    await hedron.connect(addr1).mintNative(3, stake4.stakeId);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake4.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake4.stakeShares.mul(90).div(10));

    expect(addr1Balance).to.equal(addr1ExpectedBalance);
  });

  it("Should be able to initialize and destroy an instanced HEX stake.", async function () {
    const HSIM = await ethers.getContractFactory("HEXStakeInstanceManager");
    hsim = await HSIM.attach(hedron.hsim());

    // deposit HEX to HSIM
    await hex.connect(addr1).approve(hedron.hsim(), 10000000000);

    // start stake
    await expect(hsim.connect(addr1).hexStakeStart(20000000000, 1)
    ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");

    await hsim.connect(addr1).hexStakeStart(10000000000, 1);
    hexBalance = await hex.balanceOf(addr1.address);
    hsiAddress = await hsim.hsiLists(addr1.address, 0);

    // end pending stake (cancel)
    await hsim.connect(addr1).hexStakeEnd(0, hsiAddress);

    newhexBalance = await hex.balanceOf(addr1.address);

    expect(hexBalance.add(10000000000)).to.equal(newhexBalance);
  });

  it("Should pass instanced HEX stake minting sanity checks.", async function () {
    await hex.connect(addr1).approve(hedron.hsim(), 30000000000);

    // start stakes
    await hsim.connect(addr1).hexStakeStart(10000000000, 1);
    hsiAddress = await hsim.hsiLists(addr1.address, 0);

    await hsim.connect(addr1).hexStakeStart(10000000000, 1);
    hsiAddress2 = await hsim.hsiLists(addr1.address, 1);

    // test invalid stake
    await expect(hedron.connect(addr1).mintInstanced(0, addr1.address)
    ).to.be.revertedWith("HDRN: HSI index address mismatch");

    // test pending stake
    await expect(hedron.connect(addr1).mintInstanced(0, hsiAddress)
    ).to.be.revertedWith("HDRN: cannot mint against a pending HEX stake");

    // loan second stake
    await hedron.connect(addr1).loanInstanced(1, hsiAddress2)

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test loaned stake
    await expect(hedron.connect(addr1).mintInstanced(1, hsiAddress2)
    ).to.be.revertedWith("HDRN: cannot mint against a loaned HEX stake");

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test first stake
    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).mintInstanced(0, hsiAddress);
    stake1 = await hex.stakeLists(hsiAddress, 0);

    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake1.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake1.stakeShares.mul(90).div(10));
    addr1Balance = await hedron.balanceOf(addr1.address);

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // create third stake
    await hsim.connect(addr1).hexStakeStart(10000000000, 10);
    hsiAddress3 = await hsim.hsiLists(addr1.address, 2);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test third stake zero days served
    addr1ExpectedBalance = await hedron.balanceOf(addr1.address);

    await hedron.connect(addr1).mintInstanced(2, hsiAddress3);
    stake3 = await hex.stakeLists(hsiAddress3, 0);

    addr1Balance = await hedron.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test third stake one day served
    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).mintInstanced(2, hsiAddress3);

    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares.mul(90).div(10));
    addr1Balance = await hedron.balanceOf(addr1.address);

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // move to next Hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // test third stake two days served
    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).mintInstanced(2, hsiAddress3);
    
    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake3.stakeShares.mul(90).div(10));
    addr1Balance = await hedron.balanceOf(addr1.address);
    
    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // end stake
    await hsim.connect(addr1).hexStakeEnd(0, hsiAddress);
    await hsim.connect(addr1).hexStakeEnd(0, hsiAddress3);
    await expect(hsim.connect(addr1).hexStakeEnd(0, hsiAddress2)
    ).to.be.revertedWith("HSIM: Cannot call stakeEnd against a loaned stake");
  });

  it("Should pass loan sanity checks.", async function () {

    // deposit HEX to HSIM
    await hex.connect(addr1).approve(hedron.hsim(), 60000000000);

    // start stake
    await hsim.connect(addr1).hexStakeStart(10000000000, 1000);
    hsiAddress1 = await hsim.hsiLists(addr1.address, 1);
    stake1 = await hex.stakeLists(hsiAddress1, 0);

    // invalid stake
    await expect(hedron.connect(addr1).loanInstanced(1, addr1.address)
    ).to.be.revertedWith("HDRN: HSI index address mismatch");

    // loan stake
    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).loanInstanced(1, hsiAddress1);

    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.add(stake1.stakeShares.mul(1000));
    addr1Balance = await hedron.balanceOf(addr1.address);

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // try loaning again.
    await expect(hedron.connect(addr1).loanInstanced(1, hsiAddress1)
    ).to.be.revertedWith("HDRN: HSI loan already exists");

    // start second stake
    await hsim.connect(addr1).hexStakeStart(10000000000, 100);
    hsiAddress2 = await hsim.hsiLists(addr1.address, 2);
    stake2 = await hex.stakeLists(hsiAddress2, 0);

    // move two hedron days
    await network.provider.send("evm_increaseTime", [172800])
    await ethers.provider.send('evm_mine');

    // mint second stake, check LMR bonus
    addr1Balance = await hedron.balanceOf(addr1.address);

    loanedSupply = ethers.BigNumber.from(await hedron.loanedSupply());
    totalSupply = ethers.BigNumber.from(await hedron.totalSupply());
    loanedToMinted = loanedSupply.mul(100).div(totalSupply);
    multiplier = 0;

    if (loanedToMinted > 50) {
      multiplier = loanedToMinted.sub(50).mul(2);
    }

    await hedron.connect(addr1).mintInstanced(2, hsiAddress2);

    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    tempBalance = ethers.BigNumber.from(stake2.stakeShares);
    tempBalance = tempBalance.add(stake2.stakeShares.mul(90).div(10));
    tempBalance = tempBalance.add(tempBalance.mul(multiplier).div(10));
    addr1ExpectedBalance = addr1ExpectedBalance.add(tempBalance);
    addr1Balance = await hedron.balanceOf(addr1.address);

    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    // start third stake
    await hsim.connect(addr1).hexStakeStart(10000000000, 1);
    hsiAddress3 = await hsim.hsiLists(addr1.address, 3);
    stake3 = await hex.stakeLists(hsiAddress3, 0);

    hsiIndex = await hsim.hsiCount(addr1.address);
    hsiIndex = hsiIndex.sub(1);

    // move two hedron days
    await network.provider.send("evm_increaseTime", [172800])
    await ethers.provider.send('evm_mine');

    // end third stake
    await hsim.connect(addr1).hexStakeEnd(hsiIndex, hsiAddress3);

    // move one hedron day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    // trigger daily data update
    await hedron.connect(addr1).mintNative(0, 1);

    // start a new third stake
    await hsim.connect(addr1).hexStakeStart(10000000000, 10);
    hsiAddress3 = await hsim.hsiLists(addr1.address, 3);
    stake3 = await hex.stakeLists(hsiAddress3, 0);

    loanPaymentPreCalc = await hedron.calcLoanPayment(addr1.address, 3, hsiAddress3);

    // payoff should fail here
    await expect(hedron.connect(addr1).calcLoanPayoff(addr1.address, 3, hsiAddress3)
    ).to.be.revertedWith("HDRN: Cannot payoff non-existant loan");

    // test payments / payoffs day zero of loan
    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);
    loanPaymentPostCalc = await hedron.connect(addr1).calcLoanPayment(addr1.address, 3, hsiAddress3);
    loanPayoffPostCalc = await hedron.connect(addr1).calcLoanPayoff(addr1.address, 3, hsiAddress3);

    expect(loanPaymentPreCalc[0]).to.equal(loanPaymentPostCalc[0]);
    expect(loanPaymentPreCalc[1]).to.equal(loanPaymentPostCalc[1]);
    expect(loanPaymentPreCalc[0]).to.equal(loanPayoffPostCalc[0]);
    expect(loanPaymentPreCalc[1]).to.be.gt(loanPayoffPostCalc[1]);

    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).loanPayoff(3, hsiAddress3);
    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.sub(loanPayoffPostCalc[0]).sub(loanPayoffPostCalc[1]);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);

    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).loanPayment(3, hsiAddress3);
    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.sub(loanPaymentPostCalc[0]).sub(loanPaymentPostCalc[1]);

    addr1Balance = await hedron.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);

    // move ten days, test payoff day ten of loan
    await network.provider.send("evm_increaseTime", [864000])
    await ethers.provider.send('evm_mine');

    loanPayoffPostCalc = await hedron.connect(addr1).calcLoanPayoff(addr1.address, 3, hsiAddress3);
    expect(loanPaymentPreCalc[0]).to.equal(loanPayoffPostCalc[0]);
    expect(loanPaymentPreCalc[1]).to.equal(loanPayoffPostCalc[1]);

    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).loanPayoff(3, hsiAddress3);
    addr1ExpectedBalance = ethers.BigNumber.from(addr1Balance);
    addr1ExpectedBalance = addr1ExpectedBalance.sub(loanPayoffPostCalc[0]).sub(loanPayoffPostCalc[1]);
    
    addr1Balance = await hedron.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(addr1ExpectedBalance);

    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);

    const HSI = await ethers.getContractFactory("HEXStakeInstance");
    hsi = await HSI.attach(hsiAddress3);

    expectedShare = await hsi.share();

    // move 89 days
    await network.provider.send("evm_increaseTime", [7689600])
    await ethers.provider.send('evm_mine');

    const stake = await hex.stakeLists(addr2.address, 0);
    await hedron.connect(addr2).mintNative(0, stake.stakeId);

    await expect(hedron.connect(addr2).loanLiquidate(addr1.address, 3, hsiAddress3)
    ).to.be.revertedWith("HDRN: Cannot liquidate a loan not in default");

    // move one day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    /// test loan liquidation / reallocation
    await hedron.connect(addr2).loanLiquidate(addr1.address, 3, hsiAddress3);

    // move one day
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
  
    await hedron.connect(addr2).loanLiquidateExit(0, 1);

    hsiAddress4 = await hsim.hsiLists(addr2.address, 0);
    hsi2 = await HSI.attach(hsiAddress4);
    
    share = await hsi2.share();
    
    expect(share.stake.stakeId).equals(expectedShare.stake.stakeId);

    // make another stake, test zero interest payoff
    await hsim.connect(addr1).hexStakeStart(10000000000, 100);
    hsiAddress3 = await hsim.hsiLists(addr1.address, 3);
    stake3 = await hex.stakeLists(hsiAddress3, 0);
    
    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);
    await hedron.connect(addr1).loanPayment(3, hsiAddress3);
    await hedron.connect(addr1).loanPayment(3, hsiAddress3);
    await hedron.connect(addr1).loanPayoff(3, hsiAddress3);

    // re-loan stake
    hsiAddress3 = await hsim.hsiLists(addr1.address, 3);
    stake3 = await hex.stakeLists(hsiAddress3, 0);

    await hedron.connect(addr1).loanInstanced(3, hsiAddress3);

    // move 89 days
    await network.provider.send("evm_increaseTime", [7689600])
    await ethers.provider.send('evm_mine');

    await hedron.connect(addr1).loanPayment(3, hsiAddress3);

    // move 30 days
    await network.provider.send("evm_increaseTime", [2592000])
    await ethers.provider.send('evm_mine');

    // liquidation should fail due to payment
    await expect(hedron.connect(addr2).loanLiquidate(addr1.address, 3, hsiAddress3)
    ).to.be.revertedWith("HDRN: Cannot liquidate a loan not in default");

    // move one day
    await network.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send('evm_mine');

    // liquidate
    addr2Balance = await hedron.balanceOf(addr2.address);
    oldAddr2Balance = addr2Balance;
    await hedron.connect(addr2).loanLiquidate(addr1.address, 3, hsiAddress3);

    liquidation = await hedron.liquidationList(2);
    bidAmount = liquidation.bidAmount;
    expectedAddr2Balance = await hedron.balanceOf(addr2.address);
    expectedAddr2Balance = expectedAddr2Balance.add(bidAmount);

    await expect(addr2Balance).to.equal(expectedAddr2Balance);
    bidAmount = bidAmount.add(1000);

    addr1Balance = await hedron.balanceOf(addr1.address);
    await hedron.connect(addr1).loanLiquidateBid(2, bidAmount);
    addr2Balance = await hedron.balanceOf(addr2.address);

    await expect(addr2Balance).to.equal(oldAddr2Balance);

    liquidation = await hedron.liquidationList(2);
    bidAmount = liquidation.bidAmount;
    expectedAddr1Balance = await hedron.balanceOf(addr1.address);
    expectedAddr1Balance = expectedAddr1Balance.add(bidAmount);

    await expect(addr1Balance).to.equal(expectedAddr1Balance);
    
    // move almost one day
    await network.provider.send("evm_increaseTime", [86390]);
    await ethers.provider.send('evm_mine');
  
    // liquidation exit should fail
    await expect(hedron.connect(addr2).loanLiquidateExit(0, 2))
    .to.be.revertedWith("HDRN: Cannot exit on active liquidation");

    bidAmount = bidAmount.add(1000);
    await hedron.connect(addr1).loanLiquidateBid(2, bidAmount);

    // move almost 5 minutes
    await network.provider.send("evm_increaseTime", [290]);
    await ethers.provider.send('evm_mine');
  
    // should fail
    await expect(hedron.connect(addr2).loanLiquidateExit(0, 2))
    .to.be.revertedWith("HDRN: Cannot exit on active liquidation");

    // closer to 5 minutes
    await network.provider.send("evm_increaseTime", [8]);
    await ethers.provider.send('evm_mine');

    bidAmount = bidAmount.add(1000);
    await hedron.connect(addr2).loanLiquidateBid(2, bidAmount);

    // another to 5 minutes
    await network.provider.send("evm_increaseTime", [298]);
    await ethers.provider.send('evm_mine');

    // should still fail
    await expect(hedron.connect(addr2).loanLiquidateExit(0, 2))
    .to.be.revertedWith("HDRN: Cannot exit on active liquidation");

    // finish it off
    await network.provider.send("evm_increaseTime", [1]);
    await ethers.provider.send('evm_mine');

    await hedron.connect(addr2).loanLiquidateExit(0, 2)
  });

  it("Should pass HSI NFT sanity checks.", async function () {
    const HSI = await ethers.getContractFactory("HEXStakeInstance");
    hsiAddress = await hsim.hsiLists(addr2.address, 0);
    hsi = await HSI.attach(hsiAddress);

    expectedShare = await hsi.share();

    // should not tokenize loaned stake
    hsiAddress2 = await hsim.hsiLists(addr2.address, 1);
    await hedron.connect(addr2).loanInstanced(1, hsiAddress2);
    await expect(hsim.connect(addr2).hexStakeTokenize(1, hsiAddress2)
    ).to.be.revertedWith("HSIM: Cannot tokenize a loaned stake");

    await hsim.connect(addr2).hexStakeTokenize(0, hsiAddress);
    await hsim.connect(addr2).approve(addr1.address, 1);

    // test rarible royalties
    royalties = await hsim.getRaribleV2Royalties(1);
    expect(royalties[0].value).equals(15);

    // should fail as non owner
    await expect(hsim.connect(addr1).hexStakeDetokenize(1)
    ).to.be.revertedWith("HSIM: Detokenization requires token ownership");

    // transfer to addr1
    await hsim.transferFrom(addr2.address, addr1.address, 1);

    // test rarible royalties after transfer
    royalties = await hsim.getRaribleV2Royalties(1);
    expect(royalties[0].value).equals(15);

    // make sure ERC2981 also works
    royalties = await hsim.royaltyInfo(1, 10000);
    expect(royalties.royaltyAmount).equals(15);

    // detokenize
    await hsim.connect(addr1).hexStakeDetokenize(1);

    hsiAddress = await hsim.hsiLists(addr1.address, 3);
    hsi = await HSI.attach(hsiAddress);

    share = await hsi.share();

    // make sure stakeGoodAccounting works.
    await hsi.goodAccounting();

    expect(share.stake.stakeId).equals(expectedShare.stake.stakeId);
    expect(await hsim.hsiCount(addr2.address)).to.equal(1);
    expect(await hsim.hsiCount(addr1.address)).to.equal(4);
  });

  it("Should external function call tests.", async function () {
    hsiCount = await hsim.hsiCount(addr1.address);
    stakeCount = await hsim.stakeCount(addr1.address);

    expect(hsiCount).to.equal(stakeCount);

    hsiAddress = await hsim.hsiLists(addr1.address, hsiCount.sub(1));
    const HSI = await ethers.getContractFactory("HEXStakeInstance");
    hsi = await HSI.attach(hsiAddress);
    share = await hsi.share();

    stake = await hsim.stakeLists(addr1.address, stakeCount.sub(1));

    expect(stake.stakeId).to.equal(share.stake.stakeId);

    await expect(hedron.connect(addr1).proofOfBenevolence(ethers.BigNumber.from(100))
    ).to.be.revertedWith('HDRN: Burn amount exceeds allowance');

    await hedron.connect(addr1).approve(hedron.address, ethers.BigNumber.from(100));
    //console.log(await hedron.allowance(addr1.address, hedron.address));
    await hedron.connect(addr1).proofOfBenevolence(ethers.BigNumber.from(100));

    allowance = await hedron.allowance(addr1.address, hedron.address)
    expect(allowance).equals(0);
  });
});
