// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../lib/BitMaps.sol";

contract Permissions {
    using BitMaps for BitMaps.BitMap;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdatePermissions(address indexed account, uint256 permissionBits);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized(address caller, uint256 permissionBits);

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant ADMIN_ROLE_BITS = 2 ** 1;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) internal _permissionBits;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized(uint256 permissionBits) {
        if(!hasRole(msg.sender, permissionBits)) {
            revert Unauthorized(msg.sender, permissionBits);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function hasRole(address _account, uint256 _roleBits) public view returns (bool) {
        return _permissionBits[_account] & _roleBits > 0;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function grantRole(address _account, uint256 _roleBits) external onlyAuthorized(ADMIN_ROLE_BITS) {
        _setupRole(_account, _roleBits);
    }

    function revokeRole(address _account, uint256 _roleBits) external onlyAuthorized(ADMIN_ROLE_BITS) {
        _revokeRole(_account, _roleBits);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _setupRole(address _account, uint256 _roleBits) internal {
        
        uint256 permissions = _permissionBits[_account];
        permissions |= _roleBits;
        _permissionBits[_account] = permissions;

        emit UpdatePermissions(_account, _roleBits);
    }

    function _revokeRole(address _account, uint256 _roleBits) internal {
        uint256 permissions = _permissionBits[_account];
        permissions &= ~_roleBits;
        _permissionBits[_account] = permissions;

        emit UpdatePermissions(_account, permissions);
    }
}