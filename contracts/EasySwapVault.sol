// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IEasySwapVault} from "./interface/IEasySwapVault.sol";
import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";


contract EasySwapVault is IEasySwapVault,OwnableUpgradeable{
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    address public orderBook;
    mapping(OrderKey => uint256) public ETHBalance;
    mapping(OrderKey => uint256) public NFTBalance;

    modifier onlyEasySwapOrderBook() {
        require(msg.sender == orderBook, "HV: only EasySwap OrderBook");
        _;
    }

    /**
     * 初始化函数
     */
    function initialize() external initializer {
        __ownable_init(_msgsender());
    }

    /**
     * 设置订单薄
     * @param newOrderBook 
     */
    function setOrderBook(address newOrderBook) external onlyOwner {
        require(newOrderBook != address(0), "HV: zero address");
        orderBook = newOrderBook;
    }

    /**
     * 余额查询
     * @param orderKey 
     * @return ETHAmount 
     * @return tokenId 
     */
    function balanceOf(OrderKey orderKey) external view returns (uint256 ETHAmount,uint256 tokenId) {
        ETHAmount = ETHBalance[orderKey];
        tokenId=NFTBalance[orderKey];
    }


    /**
     * 将ETH存入合约
     *  msg.value 是实际收到的 ETH，ETHAmount 只是最低要求
     * @param orderKey 
     * @param ETHAmount 
     */
    function depositETH(
        OrderKey orderKey,
        uint256 ETHAmount
    )external payable onlyEasySwapOrderBook{
        require(msg.value >= ETHAmount, "HV: not match ETHAmount");
        ETHBalance[orderKey] += msg.value;//允许超额存款，提高灵活性
    }

    /**
     * 提取ETH
     * @param orderKey 
     * @param ETHAmount 
     * @param to 
     */
    function withdrawETH(
        Orderkey orderKey,
        uint256 ETHAmount,
        address to
    )external onlyEasySwapOrderBook{
        ETHBalance[orderKey] -= ETHAmount;
        to.safeTransferETH(ETHAmount);
    }

    /**
     * 存入NFT
     * @param orderKey  订单的唯一标识符
     * @param from  NFT 的当前所有者地址
     * @param collection NFT 所属的合约地址
     * @param tokenId NFT 的唯一标识符
     */
    function depositNFT(
        OrderKey orderKey, 
        address from,  
        address collection,
        uint256 tokenId 
    )external onlyEasySwapOrderBook{
        IERC721(collection).safeTransferNFT(from, address(this), tokenId);
        NFTBalance[orderKey] = tokenId;
    }

    /**
     * 提取NFT
     * @param orderKey 
     * @param to 
     * @param collection 
     * @param tokenId 
     */
    function withdrawNFT(
        OrderKey orderKey,
        address to,
        address collection,
        uint256 tokenId
    )external onlyEasySwapOrderBook{
        require(NFTBalance[orderKey] == tokenId, "HV: not match tokenId");
        delete(NFTBalance[orderKey]);

        IERC721(collection).safeTransferNFT(address(this), to, tokenId);
    }

    /**
     * 编辑ETH
     * @param oldOrderKey 
     * @param newOrderKey 
     * @param oldETHAmount 
     * @param newETHAmount 
     * @param to 
     */
    function editETH(
        OrderKey oldOrderKey,
        OrderKey newOrderKey,
        uint256 oldETHAmount,
        uint25  newETHAmount,
        address to
    ) external payable onlyEasySwapOrderBook{
        //将旧订单的ETH余额设置为0
        ETHBalance[oldOrderKey] =0;

        if(oldETHAmount < newETHAmount){
            //如果新ETHAmount大于旧ETHAmount，则将差额存入合约
            require(msg.value >= newETHAmount - oldETHAmount, "HV: not match ETHAmount");
            ETHBalance[newOrderKey] = oldETHAmount +msg.value;
        }else if(oldETHAmount > newETHAmount){
            //如果新ETHAmount小于旧ETHAmount，则将差额退还给用户
            ETHBalance[newOrderKey] = newETHAmount;
            to.safeTransferETH(oldETHAmount - newETHAmount);
        }else{  
            //oldETHAmount == newETHAmount
            ETHBalance[newOrderKey] = oldETHAmount;
        }
    }

    /**
     * 编辑NFT
     */
    function editNFT(
        OrderKey oldOrderKey,
        OrderKey newOrderKey,
    )external onlyEasySwapOrderBook{
        NFTBalance[newOrderKey] = NFTBalance[oldOrderKey];
        delete(NFTBalance[oldOrderKey]);
    }

    /**
     * 转移ERC721
     */
    function transferERC721(
        address from,
        address to,
        LibOrder.Asset calldata asset
    )external onlyEasySwapOrderBook{
        IERC721(asset.collection).safeTransferNFT(from, to, asset.tokenId); 
    }

    /**
     * 批量转移ERC721
     */
    function batchTransferERC721(
        address to,
        LibOrder.NFTInfo[] calldata assets
    )external onlyEasySwapOrderBook{
        for(uint256 i=0;i<assets.length;i++){
            IERC721(assets[i].collection).safeTransferNFT(_msgSender(), to, assets[i].tokenId);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}

    uint256[50] private __gap;

}
