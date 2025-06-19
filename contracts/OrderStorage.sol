// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {RedBlackTreeLibrary,Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder,OrderKey} from "./libraries/LibOrder.sol";

error CannotInsertDuplicateOrder(OrderKey orderKey);

contract OrderStorage is Initializable {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    mapping(OrderKey => LibOrder.DBOrder) public orders;
    mapping(address => mapping (LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTree;

    mapping(address => mapping (LibOrder.Side => mapping (Price => LibOrder.OrderQueue))) public orderQueues;

    function __OrderStorage_init() internal initializer {}
    function __OrderStorage_init_unchained() internal onlyInitializing {}

    function onePlus(uint256 x) internal pure returns (uint256) {
        unchecked {
            return 1+x;
        }
    }

    /**
     * 获取最优价格
     *  买单 则获取最高的价格
     *  卖单 则获取最低的价格
     * @param collection 
     * @param side 
     */
    function getBestPrice(
        address collection,
        LibOrder.Side side
    ) public view returns(Price price) {
        price=(side==LibOrder.Side.Bid)
            ?priceTree[collection][side].last()//买单 则获取最高的价格
            :priceTree[collection][side].first();//卖单 则获取最低的价格
    }
    /**
     * 获取次优价格
     *  若传入的price为空，则返回最优价格
     *      买单 则获取最高的价格
     *      卖单 则获取最低的价格
     *  若传入的price不为空，则返回次优价格
     *      买单 获取比当前价格低的次高买价
     *      卖单 获取比当前价格高的次低卖价
     * @param collection 
     * @param side 
     * @param price 
     */
    function getNextBestPrice(
        address collection,
        LibOrder.Side side,
        Price   price
    )public view returns(Price nextBestPrice) {
        if(RedBlackTreeLibrary.isEmpty(price)){
            nextBestPrice=(side==LibOrder.Side.Bid)
                ?priceTree[collection][side].last()//买单 则获取最高的价格
                :priceTree[collection][side].first();//卖单 则获取最低的价格
        }else{
            nextBestPrice=(side==LibOrder.Side.Bid)
                ?priceTree[collection][side].prev(price)//买单 获取比当前价格低的次高买价
                :priceTree[collection][side].next(price);//卖单 获取比当前价格高的次低卖价
        }
    }
    /**
     * 
     * @param order 新增订单
     */
    function addOrder(
        LibOrder.Order memory order
    ) internal returns(OrderKey orderKey){
        // 1. 获取订单的hash
        orderKey=LibOrder.hash(order);
        //2. 判断订单是否存在
        if(orders[orderKey].order.maker!=address(0)){//地址！=0 则订单已存在
            return CannotInsertDuplicateOrder(orderKey);
        }    
        //3.价格树管理
        RedBlackTreeLibrary.Tree storage priceTree=priceTree[order.nft.collection][order.side];
        if(!priceTree.exists(order.price)){
            priceTree.insert(order.price);
        }
        //4. 订单队列管理
        LibOrder.OrderQueue storage orderQueue=orderQueues[order.nft.collection][order.side][order.price];
        //队列是否初始化
        if(LibOrder.isSentinel(orderQueue.head)){
            // 创建新的队列
            orderQueues[order.nft.collection][order.side][order.price]=LibOrder.OrderQueue(
                LibOrder.ORDERKEY_SENTINEL,
                LibOrder.ORDERKEY_SENTINEL);
            orderQueue=orderQueues[order.nft.collection][order.side][order.price];
        }
        //队列为空
        if(LibOrder.isSentinel(orderQueue.tail)){
            orderQueue.head=orderKey;
            orderQueue.tail=orderKey;
             // 创建新的订单，插入队列， 下一个订单为sentinel
             orders[orderKey]=LibOrder.DBOrder(
                order,
                LibOrder.ORDERKEY_SENTINEL
             )
        }else{//队列不为空
            orders[orderQueue.tail].next=orderKey;
            orders[orderKey]=LibOrder.DBOrder(
                order,
                LibOrder.ORDERKEY_SENTINEL
            )
            orderQueue.tail=orderKey;
        }
    }
    /**
     * 删除订单
     * @param order 
     */
    function removeOrder(
        LibOrder.Order  memory order
    )internal returns(OrderKey orderKey){
        LibOrder.OrderQueue storage orderQueue=orderQueues[order.nft.collection][order.side][order.price];
        orderKey=orderQueue.head;
        OrderKey prevOrderKey;
        bool found;
        while(LibOrder.isNotSentinel(orderKey) && !found){
            LibOrder.DBOrder memory dbOrder = orders[orderKey];
            if(dbOrder.order.maker==order.maker &&
                dbOrder.order.saleKind==order.saleKind &&
                dbOrder.order.expiry==order.expiry &&
                dbOrder.order.salt==order.salt &&
                dbOrder.order.nft.tokenId==order.nft.tokenId &&
                dbOrder.order.nft.amount==order.nft.amount ){
                    OrderKey temp = orderKey; 
                    if(OrderKey.unwrap(orderQueue.head) ==OrderKey.unwrap(orderKey)){
                        orderQueue.head = dbOrder.next;
                    }else{
                        orders[prevOrderKey].next = dbOrder.next;
                    }
                    if (
                    OrderKey.unwrap(orderQueue.tail) ==
                    OrderKey.unwrap(orderKey)
                ) {
                    orderQueue.tail = prevOrderKey;
                }
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
                delete orders[temp];
                found = true;
            }else {
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
            }
        }
        if (found) {
            if (LibOrder.isSentinel(orderQueue.head)) {
                delete orderQueues[order.nft.collection][order.side][
                    order.price
                ];
                RedBlackTreeLibrary.Tree storage priceTree = priceTrees[
                    order.nft.collection
                ][order.side];
                if (priceTree.exists(order.price)) {
                    priceTree.remove(order.price);
                }
            }
        } else {
            revert("Cannot remove missing order");
        }
    }

    /**
     * 批量获取订单
     * @param collection  NFT集合地址
     * @param tokenId   特定tokenID
     * @param side  订单方向
     * @param saleKind 销售类型
     * @param count 要获取的订单数量
     * @param price 起始价格
     * @param firstOrderKey 起始订单Key
     * @return resultOrders  结果订单数组
     * @return nextOrderKey 下次查询的起始Key
     */
    function getOrders(
        address collection,
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind,
        uint256 count,
        Price price,
        OrderKey firstOrderKey
    )
        external
        view
        returns (LibOrder.Order[] memory resultOrders, OrderKey nextOrderKey)
    {
        //初始化结果数组，长度为请求的count
        resultOrders = new LibOrder.Order[](count);
        //价格处理逻辑
        if (RedBlackTreeLibrary.isEmpty(price)) {
            price = getBestPrice(collection, side);//从最优价格开始查询
        } else {
            if (LibOrder.isSentinel(firstOrderKey)) {
                price = getNextBestPrice(collection, side, price);//获取次优价格
            }
        }

        //主查询循环
        uint256 i;
        while (RedBlackTreeLibrary.isNotEmpty(price) && i < count) {
            LibOrder.OrderQueue memory orderQueue = orderQueues[collection][
                side
            ][price];
            OrderKey orderKey = orderQueue.head;
            //如果指定了firstOrderKey，先遍历到该订单位置  
            if (LibOrder.isNotSentinel(firstOrderKey)) {
                // 遍历直到找到起始订单
                while (
                    LibOrder.isNotSentinel(orderKey) &&
                    OrderKey.unwrap(orderKey) != OrderKey.unwrap(firstOrderKey)
                ) {
                    LibOrder.DBOrder memory order = orders[orderKey];
                    orderKey = order.next;
                }
                // 重置标记
                firstOrderKey = LibOrder.ORDERKEY_SENTINEL;
            }
            //订单遍历与过滤
            while (LibOrder.isNotSentinel(orderKey) && i < count) {
                LibOrder.DBOrder memory dbOrder = orders[orderKey];
                orderKey = dbOrder.next;
                //检查订单是否设置了过期时间且已过期
                if (
                    (dbOrder.order.expiry != 0 &&
                        dbOrder.order.expiry < block.timestamp)
                ) {
                    continue;
                }
                //当查询集合级买单时，跳过物品级买单
                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForCollection)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem)
                    ) {
                        continue;
                    }
                }
                // 当查询物品级买单时，只返回相同tokenId的订单
                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForItem)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem) &&
                        (tokenId != dbOrder.order.nft.tokenId)
                    ) {
                        continue;
                    }
                }

                resultOrders[i] = dbOrder.order;//将符合条件的订单加入结果数组
                nextOrderKey = dbOrder.next;// 记录下次查询起点
                i = onePlus(i);// 计数器递增（使用unchecked优化）
            }
            //当前价格层级的订单处理完后，移动到下一个价格层级
            price = getNextBestPrice(collection, side, price);
        }
    }

    /**
     * 获取最佳匹配订单
     * @param collection NFT集合地址
     * @param tokenId 特定tokenID
     * @param side 订单方向
     * @param saleKind 销售类型（集合级/物品级）
     */
    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind
    ) external view returns (LibOrder.Order memory orderResult) {
        // 获取最佳价格
        Price price = getBestPrice(collection, side);
        while (RedBlackTreeLibrary.isNotEmpty(price)) {
             // 处理当前价格层级的订单...
            LibOrder.OrderQueue memory orderQueue = orderQueues[collection][
                side
            ][price];
            OrderKey orderKey = orderQueue.head;
            while (LibOrder.isNotSentinel(orderKey)) {
                LibOrder.DBOrder memory dbOrder = orders[orderKey];
                //物品级买单过滤
                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForItem)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem) &&
                        (tokenId != dbOrder.order.nft.tokenId)
                    ) {// 跳过非目标token的订单
                        orderKey = dbOrder.next;
                        continue;
                    }
                }
                //集合级买单过滤
                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForCollection)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem)
                    ) {//跳过物品级买单
                        orderKey = dbOrder.next;
                        continue;
                    }
                }

                if (
                    (dbOrder.order.expiry == 0 ||
                        dbOrder.order.expiry > block.timestamp)
                ) {//找到有效订单
                    orderResult = dbOrder.order;
                    break;
                }
                orderKey = dbOrder.next;
            }
            //找到有效订单后立即终止搜索
            if (Price.unwrap(orderResult.price) > 0) {
                break;
            }
            price = getNextBestPrice(collection, side, price);
        }
    }

    uint256[50] private __gap;
}