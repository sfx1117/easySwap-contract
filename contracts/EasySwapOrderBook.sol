// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IEasySwapOrderBook} from "./interface/IEasySwapOrderBook.sol";
import {IEasySwapVault} from "./interface/IEasySwapVault.sol";

import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";
import {LibPayInfo} from "./libraries/LibPayInfo.sol";

import {OrderStorage} from "./OrderStorage.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {ProtocolManager} from "./ProtocolManager.sol";


contract EasySwapOrderBook is 
    Initializable, 
    ContextUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable ,
    IEasySwapOrderBook,
    OrderStorage,
    OrderValidator,
    ProtocolManager
{
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    event LogMake(
        OrderKey orderKey,
        LibOrder.Side indexed side,
        LibOrder.SaleKind indexed saleKind,
        address indexed maker,
        LibOrder.Asset nft,
        Price price,
        uint64 expiry,
        uint64 salt
    );
    event LogCancel(OrderKey indexed orderKey, address indexed maker);
    event LogWithdrawETH(address recipient, uint256 amount);
    event BatchMatchInnerError(uint256 offset, bytes msg);
    event LogSkipOrder(OrderKey orderKey, uint64 salt);
    event LogMatch(
        OrderKey indexed makeOrderKey,
        OrderKey indexed takeOrderKey,
        LibOrder.Order makeOrder,
        LibOrder.Order takeOrder,
        uint128 fillPrice
    );

    modifier onlyDelegateCall() {
        _checkDelegateCall();
        _;
    }

    address private _vault;//EasySwapVault 合约地址
    address private immutable self = address(this);


    /**
     * 公共初始化接口
     * @param newProtocolShare  协议费比例
     * @param newVault          金库地址
     * @param EIP721Name        EIP712名称
     * @param EIP721Version     EIP712版本
     */
    function initialize(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP721Name,
        string memory EIP721Version
    )  public initializer {
        __EasySwapOrderBook_init(newProtocolShare, newVault, EIP721Name, EIP721Version);
    }

    /**
     * 内部初始化函数
     * @param newProtocolShare 
     * @param newVault 
     * @param EIP721Name 
     * @param EIP721Version 
     */
    function __EasySwapOrderBook_init(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP721Name,
        string memory EIP721Version
    )  internal onlyInitializing {
        __EasySwapOrderBook_init_unchained(newProtocolShare, newVault, EIP721Name, EIP721Version);
    }

    /**
     * 核心初始化函数
     * @param newProtocolShare 
     * @param newVault 
     * @param EIP721Name 
     * @param EIP721Version 
     */
    function __EasySwapOrderBook_init_unchained(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP721Name,
        string memory EIP721Version
    ) public onlyInitializing {
        //---初始化基础功能
        __Context_init();           //初始化上下文
        __Ownable_init();           //初始化所有权，将调用者设置为所有者
        __ReentrancyGuard_init();   //初始化防重入保护
        __Pausable_init();          //初始化可暂停功能

        //----初始化订单相关功能
        __OrderStorage_init(); //初始化订单存储
        __ProtocolManager_init(newProtocolShare); //初始化协议管理器，设置协议份额
        __OrderValidator_init(EIP721Name, EIP721Version); //初始化订单验证器 设置 EIP712 相关参数

        setVault(newVault); //设置金库地址
    }

    /**
     * 创建订单
     * @param newOrders 
     */
    function makeOrders(
        LibOrder.Order[] calldata newOrders
    ) 
        external 
        payable 
        override 
        whenNotPaused //--只在合约未暂停时可用
        nonReentrant //-- 防止重入攻击
        returns(OrderKey[] memory newOrderKeys) 
    {
        
        uint256 orderLength = newOrders.length;
        newOrderKeys = new OrderKey[](orderLength);

        uint128 ETHAmount;//eth总额
        for(uint256 i=0;i<orderLength;i++){
            uint128 buyPrice;

            //如果是买单(Bid)，计算总价buyPrice = 单价 × 数量
            if(newOrders[i].side==LibOrder.Side.Bid){
                buyPrice =Price.unwrap( newOrders[i].price ) * newOrders[i].nft.amount;
            }

            //尝试创建订单
            OrderKey newOrderKey=_makeOrderTry(newOrders[i], buyPrice);
            newOrderKeys[i]=newOrderKey;

            //如果创建成功，将ETHAmount加上当前订单的ETHAmount
            if(OrderKey.unwrap(newOrderKey) !=OrderKey.unwrap(LibOrder.ORDERKEY_SENTINEL)){
                ETHAmount += buyPrice;
            }
        }

        //如果用户发送的ETH多于实际需要,将多余的部分退还给用户
        if(msg.value >ETHAmount){
            _msgSender().safeTransferETH(msg.value - ETHAmount);
        }
    }


    /**
     * 取消订单
     * @param orderKeys 
     */
    function cancleOrders(
        OrderKey[] calldata orderKeys
    ) 
        external
        override
        whenNotPaused //--只在合约未暂停时可用
        nonReentrant //-- 防止重入攻击
        returns(bool[] memory successes)
    {
        successes = new bool[](orderKeys.length);
        for(uint256 i=0;i<orderKeys.length;i++){
            successes[i] = _cancleOrderTry(orderKeys[i]);
        }
    }

    /**
     * 编辑订单
     * @param editDetails 
     */
    function editOrders(
        LibOrder.EditDetail[] calldata editDetails
    )
        external
        payable
        override
        whenNotPaused //--只在合约未暂停时可用
        nonReentrant //-- 防止重入攻击
        returns(OrderKey[] memory newOrderKeys)
    {
        newOrderKeys=new OrderKey[](editDetails.length);

        uint256 bidETHAmount;//eth总额

        for(uint256 i=0;i<editDetails.length;i++){
            (OrderKey newOrderKey,uint128 bidPrice) = _editOrderTry(editDetails[i]);
            bidETHAmount+=bidPrice;
            newOrderKeys[i]=newOrderKey;
        }
        //如果用户发送的ETH多于实际需要,将多余的部分退还给用户
        if(msg.value >bidETHAmount){
            _msgSender().safeTransferETH(msg.value - bidETHAmount);
        }
    }

    /**
     * 匹配订单（单笔）
     * @param sellOrder 
     * @param buyOrder 
     */
    function matchOrder(
        LibOrder.Order calldata sellOrder, 
        LibOrder.Order calldata buyOrder
    )
        external 
        payable 
        override 
        whenNotPaused //--只在合约未暂停时可用
        nonReentrant //-- 防止重入攻击{

        uint256 costValue=_matchOrder(sellOrder,buyOrder,msg.value);
        if(msg.value>costValue){
            _msgSender.safeTransferETH(msg.value - costValue);
        }
    }

    /**
     * 匹配订单（批量）
     * delegatecall 的工作方式
        delegatecall 是 Solidity 的一种低级调用方式，它的特点是：

        代码：执行目标合约的代码（matchOrderWithoutPayback）。

        存储：修改的是 调用合约（matchOrders 所在合约）的存储。

        msg.sender 和 msg.value：保持不变（仍然是外部调用者的地址和 ETH 值）。
     * @param matchDetails 
     */
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    )
        external
        payable
        override
        whenNotPaused //--只在合约未暂停时可用
        nonReentrant //-- 防止重入攻击
        returns (bool[] memory successes)
    {
        successes = new bool[](matchDetails.length);
        uint128 buyETHAmount;//eth总额

        for(uint256 i=0;i<matchDetails.length;i++){
            LibOrder.MatchDetail memory matchDetail=matchDetails[i];
            //使用delegatecall调用内部函数matchOrderWithoutPayback
            (bool success, bytes memory data)=address(this).delegatecall(
                abi.encodeWithSelector(
                    "matchOrderWithoutPayback((uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),(uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),uint256)",
                    matchDetail.sellOrder,
                    matchDetail.buyOrder,
                    msg.value-buyETHAmount
                )
            );
            if(success){
                successes[i]=success;
                //买单
                if(_msgSender()==matchDetail.buyOrder.maker){
                    uint128 buyPrice ;
                    buyPrice=abi.decode(data, (uint128));
                    buyETHAmount+=buyPrice;
                }   
            }else{
                emit BatchMatchInnerError(i, data);
            }
        }
        //将多余的ETH退还给用户
        if(msg.value >buyETHAmount){
            _msgSender().safeTransferETH(msg.value - buyETHAmount);
        }

    }
    function matchOrderWithoutPayback(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        uint256 msgValue
    )
        external
        payable
        whenNotPaused
        onlyDelegateCall
        returns (uint128 costValue)
    {
        costValue = _matchOrder(sellOrder, buyOrder, msgValue);
    }








    /**
     * 尝试创建订单
     * @param order 
     * @param ETHAmount 
     */
    function _makeOrderTry(
        LibOrder.Order calldata order,
        uint128 ETHAmount
    ) internal returns (OrderKey newOrderKey){
        if(order.maker==_msgSender() //只有订单创建者可以提交
            && order.price !=0  //订单价格不为0 
            && order.salt!=0    //订单salt不为0
            && (order.expiry > block.timestamp || order.expiry ==0) //订单未过期或无期限
            && filledAmount[LibOrder.hash(order)]==0    //订单未被取消或成交
        ){
            newOrderKey=LibOrder.hash(order);

            //处理卖单
            if(order.side==LibOrder.Side.List){
                //卖单NFT数量必须为1（不支持批量卖单）
                if(order.nft.amount !=1){
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                //将NFT存入金库合约
                IEasySwapVault(_vault).depositNFT(
                    newOrderKey,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId);

            }else if(order.side==LibOrder.Side.Bid){
                //处理买单
                //购买数量不能为零
                if(order.nft.amount ==0){
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                //将ETH转入金库合约
                IEasySwapVault(_vault).depositETH{value:uint256(ETHAmount)}(
                    newOrderKey,
                    ETHAmount
                );
            }
            //将订单存入订单簿
            addOrder(order);
            // 触发订单创建事件
            emit LogMake(
                newOrderKey,
                order.side,
                order.saleKind,
                order.maker,
                order.nft,
                order.price,
                order.expiry,
                order.salt
            );
        }else {
            emit LogSkipOrder(LibOrder.hash(order), order.salt);
        }
    }
    /**
     * 尝试取消订单
     * @param orderKey 
     */
    function _cancleOrderTry(OrderKey orderKey) internal returns (bool success){
        LibOrder.Order memory order = orders[orderKey].order;

        if(order.maker == _msgSender() //调用者必须是订单创建者
            && filledAmount[orderKey] < order.nft.amount //订单未完全成交（已成交数量 < 订单总量）
        ){
            OrderKey orderHash=LibOrder.hash(order);
            //调用父类的接口 从存储中删除订单
            removeOrder(order);

            //卖单 从金库取回NFT给订单创建者
            if(order.side==LibOrder.Side.List){
                IEasySwapVault(_vault).withdrawNFT(
                    orderHash,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                )
            }else if(order.side==LibOrder.Side.Bid){
                //买单 计算未成交部分的ETH金额并返还给订单创建者
                uint256 availNFTAmount=order.nft.amount - filledAmount[orderHash];
                IEasySwapVault(_vault).withdrawETH(
                    orderHash,
                    Price.wrap(order.price) * availNFTAmount,// 计算应返还ETH金额
                    order.maker
                )
            }
            _cancelOrder(orderKey);
            success=true;
            emit LogCancle(orderKey, order.maker);
        }else{
            emit LogSkipOrder(orderKey, order.salt);
        }
    }
    /**
     * 尝试编辑订单
     *  编辑订单  只允许更改price
     * @param editDetail 
     * @return newOrderKey 
     * @return deltaBidPrice 
     */
    function _editOrderTry(LibOrder.EditDetail calldata editDetail) 
            internal returns (OrderKey newOrderKey,uint128 deltaBidPrice){

        OrderKey oldOrderKey=editDetail.orderKey;
        LibOrder.Order memory newOrder = editDetail.order;
        LibOrder.Order memory oldOrder = orders[oldOrderKey].order;
        //新旧订单一致性检查
        if(newOrder.saleKind != oldOrder.saleKind 
            || newOrder.side != oldOrder.side 
            || newOrder.maker!=oldOrder.maker
            || newOrder.nft.collection !=oldOrder.nft.collection
            || newOrder.nft.tokenId !=oldOrder.nft.tokenId
            || filledAmount[oldOrderKey] >= oldOrder.nft.amount){

            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        //新订单有效性检查
        if(newOrder.maker != _msgSender() 
            || newOrder.salt==0
            || (newOrder.expiry < block.timestamp && newOrder.expiry!=0)
            || filledAmount[LibOrder.hash(newOrder)]!=0){

            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
       
        //取消旧订单
        uint256 oldFilledAmount = filledAmount[oldOrderKey];//记录已成交数量
        removeOrder(oldOrder);//从存储中移除旧订单
        _cancleOrderTry(oldOrderKey);//执行取消逻辑
        emit LogCancle(oldOrderKey, oldOrder.maker);

        //创建新订单
        OrderKey newOrderKey=addOrder(newOrder);

        //资产处理
        if(oldOrder.side==LibOrder.Side.List){//卖单(List)处理,只需更新金库中的订单Key映射
            IEasySwapVault(_vault).editNFT(oldOrderKey,newOrderKey);
        }else if((oldOrder.side == LibOrder.Side.Bid){//买单(Bid)处理
            //计算价格差额：新总价 - 旧剩余价    
            uint256 oldRemainingPrice = Price.unwrap(oldOrder.price) *
                (oldOrder.nft.amount - oldFilledAmount);
            uint256 newRemainingPrice = Price.unwrap(newOrder.price) *
                newOrder.nft.amount;
            //如果需要更多ETH，通过value转账补充
            if(newRemainingPrice >oldRemainingPrice){
                deltaBidPrice=newRemainingPrice - oldRemainingPrice;
                IEasySwapVault(_vault).editETH{value:uint256(deltaBidPrice)}(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker);
            }else{
                //如果价格降低，金库会返还差额
                IEasySwapVault(_vault).editETH(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker
                );
            }
        }
        emit LogMake(
            newOrderKey,
            newOrder.side,
            newOrder.saleKind,
            newOrder.maker,
            newOrder.nft,
            newOrder.price,
            newOrder.expiry,
            newOrder.salt
        );
    }

    /**
     * 匹配订单
     * @param sellOrder 
     * @param buyOrder 
     * @param msgValue 
     */
    function _matchOrder(
        LibOrder.order calldata sellOrder,
        LibOrder.order calldata buyOrder,
        uint256 msgValue
    )
    internal returns (uint256 costValue){

        OrderKey sellOrderKey=LibOrder.hash(sellOrder);
        OrderKey buyOrderKey=LibOrder.hash(buyOrder);
        _isMatchAvailable(sellOrder,buyOrder,sellOrderKey,buyOrderKey);

        //卖单
        if(_msgSender()==sellOrder.maker){
            require(msgValue==0,"msgValue must be 0");
            bool isSellExist=orders[sellOrderKey].order.maker != address(0);
            _validateOrder(sellOrder,isSellExist);
            _validateOrder(orders[buyOrderKey].order,false);

            //以买单价格为成交价
            uint256 fillPrice=Price.unwrap(buyOrder.price);
            if(isSellExist){
                removeOrder(sellOrder);
                _updateFilledAmount(sellOrder.nft.amount,sellOrderKey);
            }
            _updateFilledAmount(filledamount[buyOrderKey]+1,buyOrderKey);

            emit LogMatch(sellOrderKey,buyOrderKey,sellOrder,buyOrder,fillPrice);
            //从金库中提取ETH
            IEasySwapVault(_vault).withdrawETH(buyOrderKey,fillPrice,address(this));
            //协议费
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            //将ETH发送给卖单maker
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            //向卖方转移NFT
            if(isSellExist){
                IEasySwapVault(_vault).withdrawNFT(
                    sellOrderKey,
                    buyOrder.maker,
                    sellOrder.nft.collection,
                    sellOrder.nft.tokenId);
            }else{
                IEasySwapVault(_vault).transferERC721(
                    sellOrder.maker,
                    buyOrder.maker,
                    sellOrder.nft
                );
            }
        }else if(_msgSender()==buyOrder.maker){//买单
            bool isBuyExist=orders[buyOrderKey].order.maker != address(0);
            //检查买方订单是否已存在  
            _validateOrder(buyOrder,isBuyExist);
            //验证卖单的有效性
            _validateOrder(orders[sellOrderKey].order,false);

            uint256 buyPrice=Price.unwrap(buyOrder.price);
            uint256 fillPrice=Price.unwrap(sellOrder.price);
            
            if(!isBuyExist){ //若买单不存在
                require(msgValue>=fillPrice,"HD: value < fill price");
            }else{
                require(buyPrice>=fillPrice,"HD: value < fill price");
                //从金库中提取ETH
                IEasySwapVault(_vault).withdrawETH(
                    buyOrderKey,
                    buyPrice,
                    address(this)
                );
                removeOrder(buyOrder);
                _updateFilledAmount(filledamount[buyOrderKey]+1,buyOrderKey);
            }
            _updateFilledAmount(sellOrder.nft.amount,sellOrderKey);

            emit LogMatch(buyOrderKey,sellOrderKey,buyOrder,sellOrder,fillPrice);
            //协议费
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            //将ETH发送给卖单maker
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            //将多余的ETH退回给买方
            if(buyPrice>fillPrice){
                buyOrder.maker.safeTransferETH(buyPrice-fillPrice);
            }
            //向卖方转移NFT
            IEasySwapVault(_vault).withdrawNFT(
                sellOrderKey,
                    buyOrder.maker,
                    sellOrder.nft.collection,
                    sellOrder.nft.tokenId
            );

            costValue=isBuyExist?0:buyPrice;
        }else {
            revert("HD: sender invalid");
        }
    }


    /**
     * 卖单、买单匹配校验
     * @param sellOrder 
     * @param buyOrder 
     * @param sellOrderKey 
     * @param buyOrderKey 
     */
    function _isMatchAvailable(
        LibOrder.order calldata sellOrder,
        LibOrder.order calldata buyOrder,
        OrderKey sellOrderKey,
        OrderKey buyOrderKey
    ) internal view{
        require(OrderKey.unwrap(sellOrderKey)!=OrderKey.unwrap(buyOrderKey),"HD: same order");
         require(
            sellOrder.side == LibOrder.Side.List &&
                buyOrder.side == LibOrder.Side.Bid,
            "HD: side mismatch"
        );
        require(
            sellOrder.saleKind == LibOrder.SaleKind.FixedPriceForItem,
            "HD: kind mismatch"
        );
        require(sellOrder.maker != buyOrder.maker, "HD: same maker");
        require( // check if the asset is the same
            buyOrder.saleKind == LibOrder.SaleKind.FixedPriceForCollection ||
                (sellOrder.nft.collection == buyOrder.nft.collection &&
                    sellOrder.nft.tokenId == buyOrder.nft.tokenId),
            "HD: asset mismatch"
        );
        require(
            filledAmount[sellOrderKey] < sellOrder.nft.amount &&
                filledAmount[buyOrderKey] < buyOrder.nft.amount,
            "HD: order closed"
        );
    }

    /**
     * 计算协议费
     * @param total 
     * @param share 
     */
    function _shareToAmount(
        uint128 total,
        uint128 share
    ) internal pure returns (uint128) {
        return (total * share) / LibPayInfo.TOTAL_SHARE;
    }
            

    function _checkDelegateCall() private view {
        require(address(this) != self);
    }

    function setVault(address newVault) public onlyOwner {
        require(newVault != address(0), "HD: zero address");
        _vault = newVault;
    }

    function withdrawETH(
        address recipient,
        uint256 amount
    ) external nonReentrant onlyOwner {
        recipient.safeTransferETH(amount);
        emit LogWithdrawETH(recipient, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}

    uint256[50] private __gap;
}