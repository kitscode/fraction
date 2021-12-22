// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./CeresPool.sol";
import "../interface/IStaking.sol";
import "../interface/IMinter.sol";
import "../interface/IRedeemer.sol";

contract CeresPoolBUSD is CeresPool {

    //****************
    // ASSETS
    //****************
    IERC20 public BUSD;
    address public busdAddress;

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor(address busd, address asc, address crs) {

        BUSD = IERC20(busd);
        busdAddress = busd;

        coinASC = ASC(asc);
        ascAddress = asc;

        coinCRS = CRS(crs);
        crsAddress = crs;
    }


    // ------------------------------------------------------------------------
    // Determine - auto mint or redeem according to the price of ASC
    // ------------------------------------------------------------------------
    function determine() external onlyGovernance override {

        uint256 ascPrice = ceresAnchor.getASCPrice();
        uint256 crsPrice = ceresAnchor.getCRSPrice();
        uint256 busdPrice = ceresAnchor.getBUSDPrice();
        uint256 colRatio = ceresAnchor.collateralRatio();

        uint256 ascValue;
        if (ascPrice > PRICE_TARGET + ceresAnchor.priceBand()) {

            ascValue = nextMintValue();
            mint(ascValue * colRatio / busdPrice, ascValue * (CERES_PRECISION - colRatio) / crsPrice, ascValue);
            lastMintRatio = ascPrice - PRICE_TARGET;
        } else if (ascPrice < PRICE_TARGET - ceresAnchor.priceBand()) {

            ascValue = nextRedeemValue();
            uint256 colRatioSquare = colRatio ** 2;
            redeem(ascValue, ascValue * colRatioSquare / busdPrice / CERES_PRECISION,
                ascValue * (CERES_PRECISION ** 2 - colRatioSquare) / crsPrice / CERES_PRECISION);
            lastRedeemRatio = PRICE_TARGET - ascPrice;
        }

        // update cr
        ceresAnchor.updateCollateralRatio();
    }


    // ------------------------------------------------------------------------
    // Calculate the mint value next time
    // ------------------------------------------------------------------------
    function nextMintValue() public view returns (uint256){

        // v1: circulating calcu
        uint256 v1 = ceresAnchor.CiRate() * coinASC.totalSupply() * ceresAnchor.Cp() / CERES_PRECISION ** 2;

        // v2: collateral calcu
        address BUSDStakingAddr = stakingAddress[busdAddress];
        address crsStakingAddr = stakingAddress[crsAddress];

        uint256 vCol = IPool(BUSDStakingAddr).collateralBalance() * ceresAnchor.Vp() * (uint256(10) ** coinASC.decimals())
        / ceresAnchor.collateralRatio() / CERES_PRECISION;
        uint256 vCrs = IPool(crsStakingAddr).collateralBalance() * ceresAnchor.Vp() * (uint256(10) ** coinASC.decimals())
        / (CERES_PRECISION - ceresAnchor.collateralRatio()) / CERES_PRECISION;

        uint256 v2 = SafeMath.min(vCol, vCrs);

        return SafeMath.min(v1, v2);
    }


    // ------------------------------------------------------------------------
    // Calculate the redeem value next time
    // ------------------------------------------------------------------------
    function nextRedeemValue() public view returns (uint256){

        uint256 v1 = ceresAnchor.CiRate() * coinASC.totalSupply() * ceresAnchor.Cp() / CERES_PRECISION ** 2;
        uint256 v2 = collateralBalance() * ceresAnchor.Vp() * (uint256(10) ** coinASC.decimals())
        / ceresAnchor.collateralRatio() / CERES_PRECISION;

        return SafeMath.min(v1, v2);
    }


    function mint(uint256 busdAmount, uint256 crsAmount, uint256 ascOut) internal override {

        uint256 colRaito = ceresAnchor.collateralRatio();

        // seigniorage
        uint256 ascToSeign = ascOut * ceresAnchor.seignioragePercent() / CERES_PRECISION;

        // staking mint
        uint256 ascToBusd = (ascOut - ascToSeign) * colRaito / CERES_PRECISION;
        uint256 ascToCrs = ascOut - ascToSeign - ascToBusd;

        address busdStakingAddr = stakingAddress[busdAddress];
        address crsStakingAddr = stakingAddress[crsAddress];

        // notify mint
        IMinter(busdStakingAddr).notifyMint(ascToBusd, busdAmount);
        IMinter(crsStakingAddr).notifyMint(ascToCrs, crsAmount);

        // mint to
        if (ascToSeign > 0)
            coinASC.poolMint(seigniorageGovern, ascToSeign);

        coinASC.poolMint(busdStakingAddr, ascToBusd);
        coinASC.poolMint(crsStakingAddr, ascToCrs);

    }

    function redeem(uint256 ascAmount, uint256 busdOut, uint256 crsOut) internal override {

        address ascStakingAddr = stakingAddress[ascAddress];

        // nofity redeem
        IRedeemer(ascStakingAddr).notifyRedeem(ascAmount, crsOut, busdOut);

        // collateral transfer to staking
        BUSD.transfer(ascStakingAddr, busdOut);

        // crs mint to staking
        coinCRS.poolMint(ascStakingAddr, crsOut);

    }


    // ------------------------------------------------------------------------
    // Get collateral balalce of this pool in USD - ceres decimals
    // ------------------------------------------------------------------------
    function collateralBalance() public override view returns (uint256){
        return BUSD.balanceOf(address(this)) * ceresAnchor.getBUSDPrice() / uint256(10) ** BUSD.decimals();
    }


    // ------------------------------------------------------------------------
    // Pool migration
    // ------------------------------------------------------------------------
    function migrate(address newPool) external onlyOwner {
        uint256 amount = BUSD.balanceOf(address(this));
        BUSD.transfer(newPool, amount);
    }

}
