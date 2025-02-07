//Use the lisence here: MIT & Apachai standart
//@dev/Developer = Pavan Ananth Sharma
//@.NET/Network = Kovan Test Network
pragma solidity ^0.6.5;
import "./FlashLoanReceiverBase.sol";
import "./ILendingPoolAddressesProvider.sol";
import "./ILendingPool.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/docs-v3.x/contracts/token/ERC20/IERC20.sol";

interface IOrderPool {
    function executeOrder(
        uint256 index,
        uint256 result,
        address[] calldata path,
        address[] calldata adapters,
        address flashloanContract
    ) external;

       function orders(uint256)
        external
        view
        returns (
            string memory name,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOut,
            uint256 minProfit,
            uint256 steps,
            uint256 result,
            uint256 status
        );
}

contract FlashloanV1 is FlashLoanReceiverBaseV1 {
    address public orderPoolAddress;

    address constant POLYGON_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant AVAX_USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address addressProvider = 0x0000000000000000000000000000000000000000;
    
    constructor(address _orderPool)
        public
        FlashLoanReceiverBaseV1(addressProvider)
    {
        orderPoolAddress = _orderPool;
            // Approve USDT spending for OrderPool
        IERC20(AVAX_USDC).approve(orderPoolAddress, 9999999999999000000);
    }

    function flashloan(
        uint256 orderIndex,
        uint256 result,
        address[] memory path,
        address[] memory adapters
    ) public {
          (
            ,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOut,
            ,
            uint256 steps,
            ,

        ) = IOrderPool(orderPoolAddress).orders(orderIndex);
        
        address _asset = tokenIn; //Avalanche USDC
        uint16 referralCode = 0;
        uint256 amount = amountIn;

        // Encode the parameters for order execution
        bytes memory data = abi.encode(orderIndex, result, path, adapters);

        ILendingPoolV1 lendingPool = ILendingPoolV1(
            0x794a61358D6845594F94dc1DB02A252b5b4814aD
        );
        lendingPool.flashLoanSimple(
            address(this),
            _asset,
            amount,
            data,
            referralCode
        );
    }

    function executeOperation(
        address asset,
        uint256 _amount,
        uint256 _fee,
        address initiator,
        bytes calldata _params
    ) external override returns (bool) {
        require(
            _amount <= getBalanceInternal(address(this), asset),
            "Invalid balance, was the flashLoan successful?"
        );

        // Decode parameters for OrderPool execution
        (uint256 orderIndex, uint256 result, address[] memory path, address[] memory adapters) = abi.decode(
            _params,
            (uint256, uint256, address[], address[])
        );

    

        // Execute the order on OrderPool
        IOrderPool(orderPoolAddress).executeOrder(
            orderIndex,
            result,
            path,
            adapters,
            address(this)
        );

        uint256 totalDebt = _amount.add(_fee);

        // Approve the Aave Pool contract to take repayment
        IERC20(asset).approve(
            0x794a61358D6845594F94dc1DB02A252b5b4814aD,
            totalDebt
        );

        return true;
    }

    function setOrderPoolAddress(address _newAddress) external onlyOwner {
        IERC20(AVAX_USDC).approve(orderPoolAddress, 0);
        orderPoolAddress = _newAddress;
        IERC20(AVAX_USDC).approve(orderPoolAddress, 9999999999999000000);
    }

    // Add safety functions to recover tokens if needed
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAmount > 0, "zero amount");
        IERC20(_tokenAddress).transfer(msg.sender, _tokenAmount);
    }
}