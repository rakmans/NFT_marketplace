// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract marketplace is ERC1155Holder, ERC721Holder {
    error onlyCreatorCanCall();
    /// @notice Type of the tokens that can be listed for sale.
    enum TokenType {
        ERC1155,
        ERC721
    }
    enum ListingType {
        Sale,
        Auction
    }

    struct Bid {
        uint256 listingId;
        address bidder;
        uint256 bid;
    }

    struct Listing {
        uint256 id;
        address tokenContract;
        uint256 tokenId;
        TokenType tokenType;
        address creator;
        address paymentToken;
        uint256 price;
        uint256 start;
        uint256 end;
        uint256 quantity;
        bool ended;
        bool isAuction;
        address highestBidder;
        uint256 highestBid;
        // this [check]
        bool deleted;
    }

    // listingId => bidder => bid bids;
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(address => bool) public deposited;

    // this [check]
    Listing[] Listings;

    modifier onlyCreator(uint256 _listingId) {
        address creator = Listings[_listingId].creator;
        if (msg.sender != creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }

    constructor() {}
    //approve and cancel [check]
    function createList(
        address _tokenContract,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity,
        bool _isAuction
    ) external {
        require(_price != 0, "");
        require(_durationUntilEnd != 0, "");
        require(_quantity != 0, "");
        address creator = msg.sender;
        TokenType tokenType = getTokenType(_tokenContract);
        _quantity = tokenType == TokenType.ERC721 ? 1 : _quantity;
        validateToken(_tokenContract, _tokenId, creator, _quantity, tokenType);
        if (_isAuction) {
            if (tokenType == TokenType.ERC721) {
                IERC721(_tokenContract).safeTransferFrom(
                    creator,
                    address(this),
                    _tokenId
                );
            } else {
                IERC1155(_tokenContract).safeTransferFrom(
                    creator,
                    address(this),
                    _tokenId,
                    _quantity,
                    ""
                );
            }
        }
        uint256 highestBid = _isAuction ? _price : 0;
        Listing memory newListing = Listing(
            Listings.length,
            _tokenContract,
            _tokenId,
            tokenType,
            creator,
            _paymentToken,
            _price,
            block.timestamp,
            block.timestamp + _durationUntilEnd,
            _quantity,
            _isAuction,
            false,
            address(0),
            highestBid,
            false
        );
        Listings.push(newListing);
    }

    function editListing(
        uint256 _listingId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity
    ) external onlyCreator(_listingId) {
        require(_price != 0, "");
        require(_durationUntilEnd != 0, "");
        require(_quantity != 0, "");
        Listing memory target = Listings[_listingId];
        address creator = target.creator;
        bool isAuction = target.isAuction;
        TokenType tokenType = target.tokenType;
        if (tokenType == TokenType.ERC721) {
            _quantity = 1;
        }
        Listing memory newListing = Listing(
            _listingId,
            target.tokenContract,
            target.tokenId,
            tokenType,
            creator,
            _paymentToken,
            _price,
            target.start,
            block.timestamp + _durationUntilEnd,
            _quantity,
            target.isAuction,
            false,
            address(0),
            target.highestBid,
            false
        );
        if (isAuction && tokenType == TokenType.ERC1155) {
            IERC1155(target.tokenContract).safeTransferFrom(
                address(this),
                creator,
                target.tokenId,
                target.quantity,
                ""
            );
            validateToken(
                target.tokenContract,
                target.tokenId,
                creator,
                _quantity,
                target.tokenType
            );
            IERC1155(target.tokenContract).safeTransferFrom(
                creator,
                address(this),
                target.tokenId,
                _quantity,
                ""
            );
        }
        Listings[_listingId] = newListing;
    }

    function cancelListing(uint256 _listingId)
        external
        onlyCreator(_listingId)
    {
        Listing memory target = Listings[_listingId];
        if(target.isAuction){
            target.deleted = true;
            Listings[_listingId] = target; 
            // event 
        }else{
            target.deleted = true;
            Listings[_listingId] = target; 
            // event
        }
    }

    /// @dev Returns the interface supported by a contract.
    function getTokenType(address _assetContract)
        internal
        view
        returns (TokenType tokenType)
    {
        if (
            IERC165(_assetContract).supportsInterface(
                type(IERC1155).interfaceId
            )
        ) {
            tokenType = TokenType.ERC1155;
        } else if (
            IERC165(_assetContract).supportsInterface(type(IERC721).interfaceId)
        ) {
            tokenType = TokenType.ERC721;
        } else {
            revert("token must be ERC1155 or ERC721.");
        }
    }

    function validateToken(
        address _token,
        uint256 _tokenId,
        address _owner,
        uint256 _quantity,
        TokenType _tokenType
    ) internal view {
        if (_tokenType == TokenType.ERC721) {
            IERC721 token = IERC721(_token);
            address owner = token.ownerOf(_tokenId);
            require(_owner == owner, "");
            address approved = token.getApproved(_tokenId);
            require(approved == address(this), "");
        } else {
            IERC1155 token = IERC1155(_token);
            uint256 quantity = token.balanceOf(_owner, _tokenId);
            require(_quantity == quantity, "");
            bool isApprove = token.isApprovedForAll(_owner, address(this));
            require(isApprove, "");
        }
    }
}
