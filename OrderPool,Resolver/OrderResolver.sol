
// File: contracts/interface/IERC20.sol


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
// File: contracts/lib/BytesToTypes.sol

// From https://github.com/pouladzade/Seriality/blob/master/src/BytesToTypes.sol (Licensed under Apache2.0)

pragma solidity >=0.7.0;

library BytesToTypes {

    function bytesToAddress(uint _offst, bytes memory _input) internal pure returns (address _output) {
        
        assembly {
            _output := mload(add(_input, _offst))
        }
    }

    function bytesToUint256(uint _offst, bytes memory _input) internal pure returns (uint256 _output) {
        
        assembly {
            _output := mload(add(_input, _offst))
        }
    } 
}

// File: contracts/lib/BytesManipulation.sol


pragma solidity >=0.7.0;


library BytesManipulation {

    function toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function toBytes(address x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function mergeBytes(bytes memory a, bytes memory b) public pure returns (bytes memory c) {
        // From https://ethereum.stackexchange.com/a/40456
        uint alen = a.length;
        uint totallen = alen + b.length;
        uint loopsa = (a.length + 31) / 32;
        uint loopsb = (b.length + 31) / 32;
        assembly {
            let m := mload(0x40)
            mstore(m, totallen)
            for {  let i := 0 } lt(i, loopsa) { i := add(1, i) } { mstore(add(m, mul(32, add(1, i))), mload(add(a, mul(32, add(1, i))))) }
            for {  let i := 0 } lt(i, loopsb) { i := add(1, i) } { mstore(add(m, add(mul(32, add(1, i)), alen)), mload(add(b, mul(32, add(1, i))))) }
            mstore(0x40, add(m, add(32, totallen)))
            c := m
        }
    }

    function bytesToAddress(uint _offst, bytes memory _input) internal pure returns (address) {
        return BytesToTypes.bytesToAddress(_offst, _input);
    }

    function bytesToUint256(uint _offst, bytes memory _input) internal pure returns (uint256) {
        return BytesToTypes.bytesToUint256(_offst, _input);
    } 

}

// File: contracts/lib/SafeMath.sol


pragma solidity >=0.7.0;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'SafeMath: ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'SafeMath: ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'SafeMath: ds-math-mul-overflow');
    }
}
// File: contracts/order/OrderResolver.sol


pragma solidity >=0.8.0;





interface IRouter {
    function ADAPTERS(uint256) external view returns (address);

    function adaptersCount() external view returns (uint256);

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

    struct Query {
        address adapter;
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
    }

    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }
}

interface IFlashloan {
    function flashloan(
        uint256 index,
        uint256 result,
        address[] memory path,
        address[] memory adapters
    ) external;
}
interface IOrderPool {

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

interface IResolver {
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload);
}

contract OrderResolver {
    using SafeMath for uint256;
    address payable public ORDERPOOL;
    address public ROUTER;

    event logs_uint256arr(uint256[] amounts);
    event log_uint256(uint256);
    event log_address(address);
    event log_string(string);
    event Response(bool success, bytes data);

    struct Opportunity {
        address token;
        uint256 amountin;
        uint256 amountout;
        uint256 profit;
        uint256 timestamp;
    }

    Opportunity public bestone;

    address constant USDTe = 0xc7198437980c041c805A1EDcbA50c1Ce5db95118;
    address constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant USDCe = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address constant USDt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;

    uint256 decimals = 6;
    event Logs(string memo, uint256 indexed number);

    constructor(address payable _ORDERPOOL, address _ROUTER) {
        ORDERPOOL = _ORDERPOOL;
        ROUTER = _ROUTER;
    }


    function setOrderPool(address payable _ORDERPOOL) public {
        ORDERPOOL = _ORDERPOOL;
    }

    function setRouter(address _ROUTER) public {
        ROUTER = _ROUTER;
    }
    function checker(uint256 offerIndex)
        external

        view
        returns (bool canExec, bytes memory execPayload)
    {
        (
            ,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOut,
            ,
            uint256 steps,
            ,

        ) = IOrderPool(ORDERPOOL).orders(offerIndex);
        (canExec, execPayload) = _checker(
            offerIndex,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            steps
        );
    }

    function checkerWithoutCompare(uint256 offerIndex)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        (
            ,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOut,
            ,
            uint256 steps,
            ,

        ) = IOrderPool(ORDERPOOL).orders(offerIndex);
        (canExec, execPayload) = _checker(
            offerIndex,
            tokenIn,
            tokenOut,
            amountIn,
            0, // expected amount out
            steps
        );
    }

    function _checker(
        uint256 offerIndex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 steps
    ) internal view returns (bool canExec, bytes memory execPayload) {
        ApexRouter.FormattedOffer memory bestpath = IRouter(ROUTER)
            .findBestPath(amountIn, tokenIn, tokenOut, steps);
        uint256 length = bestpath.amounts.length;
        uint256 bestpath_amountout;
        if (length > 0) bestpath_amountout = bestpath.amounts[length - 1];

        if (bestpath_amountout >= amountOut) {
            execPayload = abi.encodeWithSelector(
                IFlashloan.flashloan.selector,
                offerIndex,
                bestpath_amountout,
                bestpath.path,
                bestpath.adapters
            );

            return (true, execPayload);
        } else {
            bytes memory answer = BytesManipulation.toBytes(bestpath_amountout);
            return (false, answer);
        }
    }

    function getBestProfit(
        address token,
        uint256 start,
        uint256 end,
        uint256 step,
        uint256 steps
    ) external view returns (uint256 bestprofit) {
        for (uint256 i = start; i <= end; i += step) {
            uint256 amountin = i * 1e6;
            uint256 amountout = getAmountOut(amountin, token, token, steps);
            uint256 profit;
            if (amountout > amountin) profit = amountout - amountin;
            if (profit > bestprofit) {
                bestprofit = profit;
            }
        }
    }

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 steps
    ) public view returns (uint256) {
        ApexRouter.FormattedOffer memory offer = IRouter(ROUTER).findBestPath(
            amountIn,
            tokenIn,
            tokenOut,
            steps
        );

        uint256 length = offer.amounts.length;
        uint256 amountout;
        if (length > 0) amountout = offer.amounts[length - 1];

        return amountout;
    }
}
