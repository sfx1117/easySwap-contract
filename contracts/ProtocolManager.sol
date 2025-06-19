// SPDX-License-Identifier: MIT
pragma solidity ^0.8.*;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import  {LibOrder} from "./libraries/LibOrder.sol";
/**
 * 管理协议费用的基础合约
 * OwnableUpgradeable //提供合约所有权管理功能
 * @title 
 * @author 
 * @notice 
 */
abstract contract ProtocolManager is 
    Initializable, 
    OwnableUpgradeable 
{
    uint128 public protocolShare;//协议手续费比例（使用uint128节省存储空间）

    event LogUpdatedProtocolShare(uint128 indexed newProtocolShare);


    /**
     * 遵循OpenZeppelin可升级合约的初始化模式
     * 分离初始化逻辑（安全最佳实践）
     * @param newProtocolShare 
     */
    function __ProtocolManager_init(
        uint128 newProtocolShare
    ) internal onlyInitializing {
        __ProtocolManager_init_unchained( newProtocolShare);
    }

    function __ProtocolManager_init_unchained(
        uint128 newProtocolShare
    ) internal onlyInitializing {
        _setProtocolShare(newProtocolShare);
    }
    /**
     * 外部设置函数
     * @param newProtocolShare 
     */
    function setProtocolShare(
        uint128 newProtocolShare
    ) external onlyOwner {
        _setProtocolShare(newProtocolShare);
    }
    /**
     * 内部设置逻辑
     * @param newProtocolShare 
     */
    function _setProtocolShare(uint128 newProtocolShare) internal {
        require(
            newProtocolShare <= LibPayInfo.MAX_PROTOCOL_SHARE,
            "PM: exceed max protocol share"
        );
        protocolShare = newProtocolShare;
        emit LogUpdatedProtocolShare(newProtocolShare);
    }

    uint256[50] private __gap;
}