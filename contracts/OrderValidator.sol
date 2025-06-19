// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {LibOrder,OrderKey} from "./libraries/LibOrder.sol";
import {Price} from "./libraries/RedBlackTreeLibrary.sol";

abstract contract OrderValidator is Initializable, ContextUpgradeable, EIP712Upgradeable {
    
    bytes4 private constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;//EIP-1271：合约钱包验证标准魔数
    
    uint256 private constant CANCELLED = type(uint256).max;//CANCELLED：用uint256最大值表示订单取消状态
    //记录订单已成交数量
    //值为CANCELLED表示订单已取消
    mapping(OrderKey => uint256) public filledAmount;

    /**
     * 初始化函数
     * 设置EIP-712域分隔符（名称和版本）
     * 分离初始化逻辑（遵循"链式初始化"最佳实践）
     * @param EIP712Name 
     * @param EIP712Version 
     */
    function __OrderValidator_init(
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __Context_init();
        __EIP712_init(EIP712Name, EIP712Version);
        __OrderValidator_init_unchained();
    }

    function __OrderValidator_init_unchained() internal onlyInitializing {}

    /**
     * 订单验证逻辑
     * 1.必须存在有效maker地址
     * 2.salt不能为0（防止重复攻击）
     * 3.可选过期检查（0表示永不过期）
     * 4.卖单必须关联有效NFT集合
     * 5.买单价格必须大于0
     * @param order 
     * @param isSkipExpiry 
     */
    function _validateOrder(
        LibOrder.Order memory order,
        bool isSkipExpiry
    ) internal view {
        // Order must have a maker.
        require(order.maker != address(0), "OVa: miss maker");
        // Order must be started and not be expired.

        if (!isSkipExpiry) { // 过期检查
            require(
                order.expiry == 0 || order.expiry > block.timestamp,
                "OVa: expired"
            );
        }
        // Order salt cannot be 0.
        require(order.salt != 0, "OVa: zero salt");
        //卖单检查
        if (order.side == LibOrder.Side.List) {
            require(
                order.nft.collection != address(0),
                "OVa: unsupported nft asset"
            );
        } else if (order.side == LibOrder.Side.Bid) {//买单检查
            require(Price.unwrap(order.price) > 0, "OVa: zero price");
        }
    }

    /**
     * 获取成交数量 
     *      检查订单是否已取消
     *      返回当前成交数量（0表示未成交）
     * @param orderKey 
     */
    function _getFilledAmount(
        OrderKey orderKey
    ) internal view returns (uint256 orderFilledAmount) {
        // Get has completed fill amount.
        orderFilledAmount = filledAmount[orderKey];
        // Cancelled order cannot be matched.
        require(orderFilledAmount != CANCELLED, "OVa: canceled");
    }

    /**
     * 更新成交数量
     * @param newAmount 
     * @param orderKey 
     */
    function _updateFilledAmount(
        uint256 newAmount,
        OrderKey orderKey
    ) internal {
        require(newAmount != CANCELLED, "OVa: canceled");
        filledAmount[orderKey] = newAmount;
    }

    /**
     * 取消订单
     * @param orderKey 
     */
    function _cancelOrder(OrderKey orderKey) internal {
        filledAmount[orderKey] = CANCELLED;
    }

    //为未来升级预留存储空间
    //遵循OpenZeppelin可升级合约最佳实践
    uint256[50] private __gap;

}