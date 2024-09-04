// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Module} from "../../../Module.sol";
import {Role} from "../../../Role.sol";

import {UpdateMetadataCallbackERC721} from "../../../callback/UpdateMetadataCallbackERC721.sol";
import {LibString} from "@solady/utils/LibString.sol";

library BatchMetadataStorage {

    /// @custom:storage-location erc7201:token.metadata.batch
    bytes32 public constant BATCH_METADATA_STORAGE_POSITION =
        keccak256(abi.encode(uint256(keccak256("token.metadata.batch")) - 1)) & ~bytes32(uint256(0xff));

    struct Data {
        // tokenId range end
        uint256[] tokenIdRangeEnd;
        // next tokenId as range start
        uint256 nextTokenIdRangeStart;
        // tokenId range end => baseURI of range
        mapping(uint256 => string) baseURIOfTokenIdRange;
    }

    function data() internal pure returns (Data storage data_) {
        bytes32 position = BATCH_METADATA_STORAGE_POSITION;
        assembly {
            data_.slot := position
        }
    }

}

contract BatchMetadataERC721 is Module, UpdateMetadataCallbackERC721 {

    using LibString for uint256;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     *   @notice MetadataBatch struct to store metadata for a range of tokenIds.
     *   @param startTokenIdInclusive The first tokenId in the range.
     *   @param endTokenIdNonInclusive The last tokenId in the range.
     *   @param baseURI The base URI for the range.
     */
    struct MetadataBatch {
        uint256 startTokenIdInclusive;
        uint256 endTokenIdInclusive;
        string baseURI;
    }

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when uploading metadata for zero tokens.
    error BatchMetadataZeroAmount();

    /// @dev Emitted when trying to fetch metadata for a token that has no metadata.
    error BatchMetadataNoMetadataForTokenId();

    /// @dev Emitted when trying to set metadata for a token that has already metadata.
    error BatchMetadataMetadataAlreadySet();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-4906 Metadata Update.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /*//////////////////////////////////////////////////////////////
                            MODULE CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns all implemented callback and module functions.
    function getModuleConfig() external pure virtual override returns (ModuleConfig memory config) {
        config.callbackFunctions = new CallbackFunction[](2);
        config.fallbackFunctions = new FallbackFunction[](6);

        config.callbackFunctions[0] = CallbackFunction(this.onTokenURI.selector);
        config.callbackFunctions[1] = CallbackFunction(this.updateMetadataERC721.selector);

        config.fallbackFunctions[0] =
            FallbackFunction({selector: this.uploadMetadata.selector, permissionBits: Role._MINTER_ROLE});
        config.fallbackFunctions[1] =
            FallbackFunction({selector: this.setBaseURI.selector, permissionBits: Role._MANAGER_ROLE});
        config.fallbackFunctions[2] =
            FallbackFunction({selector: this.getAllMetadataBatches.selector, permissionBits: 0});
        config.fallbackFunctions[3] = FallbackFunction({selector: this.nextTokenIdToMint.selector, permissionBits: 0});
        config.fallbackFunctions[4] = FallbackFunction({selector: this.getBatchId.selector, permissionBits: 0});
        config.fallbackFunctions[5] = FallbackFunction({selector: this.getBatchRange.selector, permissionBits: 0});

        config.requiredInterfaces = new bytes4[](1);
        config.requiredInterfaces[0] = 0x80ac58cd; // ERC721.

        config.supportedInterfaces = new bytes4[](1);
        config.supportedInterfaces[0] = 0x49064906; // ERC4906.
    }

    /*//////////////////////////////////////////////////////////////
                            CALLBACK FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback function for ERC721Metadata.tokenURI
    function onTokenURI(uint256 _id) public view returns (string memory) {
        (string memory batchUri, uint256 indexInBatch) = _getBaseURI(_id);
        return string(abi.encodePacked(batchUri, indexInBatch.toString()));
    }

    /// @notice Callback function for updating metadata
    function updateMetadataERC721(address _to, uint256 _startTokenId, uint256 _quantity, string calldata _baseURI)
        external
        payable
        virtual
        override
        returns (bytes memory)
    {
        if (_startTokenId < _batchMetadataStorage().nextTokenIdRangeStart) {
            revert BatchMetadataMetadataAlreadySet();
        }
        _setMetadata(_quantity, _baseURI);
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns all metadata batches for a token.
    function getAllMetadataBatches() external view returns (MetadataBatch[] memory) {
        uint256[] memory rangeEnds = _batchMetadataStorage().tokenIdRangeEnd;
        uint256 numOfBatches = rangeEnds.length;

        MetadataBatch[] memory batches = new MetadataBatch[](rangeEnds.length);

        uint256 rangeStart = 0;
        for (uint256 i = 0; i < numOfBatches; i += 1) {
            batches[i] = MetadataBatch({
                startTokenIdInclusive: rangeStart,
                endTokenIdInclusive: rangeEnds[i] - 1,
                baseURI: _batchMetadataStorage().baseURIOfTokenIdRange[rangeEnds[i]]
            });
            rangeStart = rangeEnds[i];
        }

        return batches;
    }

    /// @notice Uploads metadata for a range of tokenIds.
    function uploadMetadata(uint256 _amount, string calldata _baseURI) external virtual {
        _setMetadata(_amount, _baseURI);
    }

    function nextTokenIdToMint() external view returns (uint256) {
        return _batchMetadataStorage().nextTokenIdRangeStart;
    }

    /// @dev Returns the id for the batch of tokens the given tokenId belongs to.
    function getBatchId(uint256 _tokenId) public view virtual returns (uint256 batchId, uint256 index) {
        uint256[] memory rangeEnds = _batchMetadataStorage().tokenIdRangeEnd;
        uint256 numOfBatches = rangeEnds.length;

        for (uint256 i = 0; i < numOfBatches; i += 1) {
            if (_tokenId < rangeEnds[i]) {
                index = i;
                batchId = rangeEnds[i];

                return (batchId, index);
            }
        }
        revert BatchMetadataNoMetadataForTokenId();
    }

    /// @dev returns the starting tokenId of a given batchId.
    function getBatchRange(uint256 _batchID) public view returns (uint256, uint256) {
        uint256[] memory rangeEnds = _batchMetadataStorage().tokenIdRangeEnd;
        uint256 numOfBatches = rangeEnds.length;

        for (uint256 i = 0; i < numOfBatches; i += 1) {
            if (_batchID == rangeEnds[i]) {
                if (i > 0) {
                    return (rangeEnds[i - 1], rangeEnds[i] - 1);
                }
                return (0, rangeEnds[i] - 1);
            }
        }

        revert BatchMetadataNoMetadataForTokenId();
    }

    /// @dev Sets the base URI for the batch of tokens with the given batchId.
    function setBaseURI(uint256 _batchId, string memory _baseURI) external virtual {
        _batchMetadataStorage().baseURIOfTokenIdRange[_batchId] = _baseURI;
        (uint256 startTokenId,) = getBatchRange(_batchId);
        emit BatchMetadataUpdate(startTokenId, _batchId);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the baseURI for a token. The intended metadata URI for the token is baseURI + indexInBatch.
    function _getBaseURI(uint256 _tokenId) internal view returns (string memory baseUri, uint256 indexInBatch) {
        uint256[] memory rangeEnds = _batchMetadataStorage().tokenIdRangeEnd;
        uint256 numOfBatches = rangeEnds.length;

        for (uint256 i = 0; i < numOfBatches; i += 1) {
            if (_tokenId < rangeEnds[i]) {
                uint256 rangeStart = 0;
                if (i > 0) {
                    rangeStart = rangeEnds[i - 1];
                }
                return (_batchMetadataStorage().baseURIOfTokenIdRange[rangeEnds[i]], _tokenId - rangeStart);
            }
        }
        revert BatchMetadataNoMetadataForTokenId();
    }

    /// @notice sets the metadata for a range of tokenIds.
    function _setMetadata(uint256 _amount, string calldata _baseURI) internal virtual {
        if (_amount == 0) {
            revert BatchMetadataZeroAmount();
        }

        uint256 rangeStart = _batchMetadataStorage().nextTokenIdRangeStart;
        uint256 rangeEndNonInclusive = rangeStart + _amount;

        _batchMetadataStorage().nextTokenIdRangeStart = rangeEndNonInclusive;
        _batchMetadataStorage().tokenIdRangeEnd.push(rangeEndNonInclusive);
        _batchMetadataStorage().baseURIOfTokenIdRange[rangeEndNonInclusive] = _baseURI;

        emit BatchMetadataUpdate(rangeStart, rangeEndNonInclusive - 1);
    }

    function _batchMetadataStorage() internal pure returns (BatchMetadataStorage.Data storage) {
        return BatchMetadataStorage.data();
    }

}
