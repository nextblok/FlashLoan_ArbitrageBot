pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity >=0.7.0;

interface IERC20 {
    event Approval(address,address,uint);
    event Transfer(address,address,uint);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
    function transferFrom(address,address,uint) external returns (bool);
    function allowance(address,address) external view returns (uint);
    function approve(address,uint) external returns (bool);
    function transfer(address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function nonces(address) external view returns (uint);  // Only tokens that support permit
    function permit(address,address,uint256,uint256,uint8,bytes32,bytes32) external;  // Only tokens that support permit
    function swap(address,uint256) external;  // Only Avalanche bridge tokens 
    function swapSupply(address) external view returns (uint);  // Only Avalanche bridge tokens 
}


pragma solidity >=0.8.0;


interface IRouter {
    function findBestPath(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps
    ) external view returns (ApexRouter.FormattedOffer memory);

    function swapNoSplit(
        ApexRouter.Trade memory _trade,
        address _to,
        uint256 _fee
    ) external;
}

interface ApexRouter {
    struct FormattedOffer {
        uint256[] amounts;
        address[] adapters;
        address[] path;
    }

    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }
}

contract OrderPool is Ownable {
    address public M_Router;

    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    
    struct Order {
        string name;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut; //expected amount out
        uint256 minProfit;
        uint256 steps;
        uint256 result; //executed result
        uint256 status; //number of execution, 1-open, ~2-executed, increasing
    }
    Order[] public orders;

    constructor(address _router) Ownable(msg.sender){
        M_Router = _router;
    }

    function setRouter(address _router) public {
        M_Router = _router;
    }

    function createOrder(
        string memory name,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minProfit,
        uint256 steps
    ) public {
        orders.push(
            Order(
                name,
                tokenIn,
                tokenOut,
                amountIn,
                amountOut,
                minProfit,
                steps,
                0,
                1
            )
        );
    }

    function editOrder(
        uint256 index,
        string memory name,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minProfit,
        uint256 steps,
        uint256 result,
        uint256 status
    ) public {
        orders[index] = Order(
            name,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            minProfit,
            steps,
            result,
            status
        );
    }

    function executeOrder(
        uint256 index,
        uint256 result,
        address[] memory path,
        address[] memory adapters,
        address flashloanContract
    ) public {
        IERC20(USDC).transferFrom(flashloanContract, address(this), orders[index].amountIn);
        uint256 beforeBalance = IERC20(USDC).balanceOf(address(this));       
        IERC20(USDC).approve(M_Router, type(uint256).max);
        
        uint256 amountIn = orders[index].amountIn;
        ApexRouter.Trade memory trade = ApexRouter.Trade(
            amountIn,
            orders[index].amountIn + orders[index].minProfit,
            path,
            adapters
        );
        IRouter(M_Router).swapNoSplit(trade, address(this), 0);
        orders[index].result = result;
        orders[index].status = orders[index].status + 1;

        uint256 afterBalance = IERC20(USDC).balanceOf(address(this));
        // require(afterBalance > beforeBalance, "balance not increased");
        IERC20(USDC).approve(M_Router, 0);        
        IERC20(USDC).transfer(flashloanContract, IERC20(USDC).balanceOf(address(this)));
    }



    // Fallback
    receive() external payable {}

    function recoverERC20(address _tokenAddress, uint256 _tokenAmount)
        external
        onlyOwner
    {
        require(_tokenAmount > 0, "zero amount");
        IERC20(_tokenAddress).transfer(msg.sender, _tokenAmount);
    }

    function recoverNative(uint256 _amount) external onlyOwner {
        require(_amount > 0, "zero amount");
        payable(msg.sender).transfer(_amount);
    }
}
