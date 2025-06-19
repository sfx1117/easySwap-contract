// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;
import {OrderKey,Price,LibOrder} from "../libraries/LibOrder.sol";

interface IEasySwapOrderBook {
    
    //创建订单
    function makeOrders(
        LibOrder.Order[] calldata newOrders
    )external payable returns(OrderKey[] memory newOrderKeys);

    //取消订单
    function cancleOrders(
        OrderKey[] calldata orderKeys
    )external returns(bool[] memory successes);

    //修改订单
    function editOrders(
        LibOrder.EditDetail[] calldata editDetails
    )external payable returns(OrderKey[] memory newOrderKeys);

    //匹配订单
    function matchOrder(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder
    )external payable;

     //匹配订单
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    )external payable returns(bool[]memory successes);

}
