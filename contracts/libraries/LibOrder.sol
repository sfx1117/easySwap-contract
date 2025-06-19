// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {Price} from "./RedBlackTreeLibrary.sol";

type OrderKey is bytes32;

library LibOrder{
    enum Side{
        List, //卖单
        Bid  //买单
    }
    enum SaleKind{
        FixedPriceForController,
        FixedPriceForItem
    }
    struct Asset{
        uint256 tokenId;
        address collection;
        uint96 amout;
    }
    struct NFTInfo{
        address collection;
        uint256 tokenId;
    }
    struct Order{
        Side side;
        SaleKind saleKind;
        address maker;
        Asset nft;
        Price price;
        uint64 expiry;
        uint64 salt;
    }

    struct DBOrder{
        Order order;
        OrderKey next;
    }
    struct OrderQueue{
        OrderKey head;
        OrderKey tail;
    }
    struct EditDetail{
        OrderKey oldOrderKey;
        LibOrder.Order newOrder;
    }
    struct MatchDetail{
        LibOrder.Order sellOrder;
        LibOrder.Order buyOrder;
    }

    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);
    bytes32 public constant ASSET_TYPEHASH =
        keccak256("Asset(uint256 tokenId,address collection,uint96 amout)");
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint8 side,uint8 saleKind,address maker,Asset nft,uint128 price,uint64 expiry,uint64 salt)Asset(uint256 tokenId,address collection,uint96 amount)"
        );
    function hash(Asset memory asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ASSET_TYPEHASH,
            asset.tokenId,
            asset.collection,
            asset.amout
        ));
    }   
    function hash(Order memory order) internal pure returns (OrderKey) {
        return OrderKey.wrap(keccak256(abi.encodePacked(
            ORDER_TYPEHASH,
            order.side,
            order.saleKind,
            order.maker,
            hash(order.nft),
            Price.unwrap(order.price),
            order.expiry,
            order.salt
        )));
    }
    function isSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) == OrderKey.unwrap(ORDERKEY_SENTINEL);
    }
    function isNotSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) != OrderKey.unwrap(ORDERKEY_SENTINEL);
    }
}
