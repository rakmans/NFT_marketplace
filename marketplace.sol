// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract marketplace is ERC1155Holder, ERC721Holder {
    using SafeERC20 for IERC20;
    error onlyCreatorCanCall();

    uint256 constant PLATFORM_FEE = 100;
    uint256 constant MAX_BPS = 10000;
    uint256 constant BID_BUFFER_BPS = 500;
    address constant PLATFORM_OWNER =
        0x417C83C2674C85010A453a7496407B72E0a30ADF;
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
        uint256 quantity;
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
        uint256 minBid;
        bool deleted;
    }

    // listingId => bidder => bid bids;
    mapping(uint256 => Bid[]) public bids;
    mapping(address => bool) public deposited;

    Listing[] Listings;

    modifier onlyCreator(uint256 _listingId) {
        address creator = Listings[_listingId].creator;
        if (msg.sender != creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }

    modifier mustNotDeleted(uint256 _listingId) {
        if (Listings[_listingId].deleted) {
            revert();
        }
        _;
    }

    constructor() {}

    function createList(
        address _tokenContract,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity,
        uint256 _minBid,
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
        _price = _isAuction ? _price : 0;
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
            _minBid,
            false
        );
        Listings.push(newListing);
        // event
    }

    //not ended
    function editListing(
        uint256 _listingId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity
    ) external onlyCreator(_listingId) mustNotDeleted(_listingId) {
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
            target.minBid,
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
        // event
    }

    //not ended
    function cancelListing(uint256 _listingId)
        external
        onlyCreator(_listingId)
        mustNotDeleted(_listingId)
    {
        Listing memory target = Listings[_listingId];
        target.deleted = true;
        if (target.isAuction) {
            if (target.tokenType == TokenType.ERC1155) {
                IERC1155(target.tokenContract).safeTransferFrom(
                    address(this),
                    target.creator,
                    target.tokenId,
                    target.quantity,
                    ""
                );
            } else {
                IERC721(target.tokenContract).safeTransferFrom(
                    address(this),
                    target.creator,
                    target.tokenId
                );
            }
            Listings[_listingId] = target;
            // event
        } else {
            Listings[_listingId] = target;
            // event
        }
    }

    //not ended
    function buy(uint256 _listingId, uint256 _quantity)
        external
        mustNotDeleted(_listingId)
    {
        Listing memory target = Listings[_listingId];
        uint256 totalPrice = target.tokenType == TokenType.ERC1155
            ? target.price * _quantity
            : target.price;
        target.quantity -= _quantity;
        target.ended = target.quantity == 0;
        Listings[_listingId] = target;
        uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
        uint256 royaltyCut;
        address royaltyRecipient;
        try
            IERC2981(target.tokenContract).royaltyInfo(
                target.tokenId,
                totalPrice
            )
        returns (address royaltyFeeRecipient, uint256 royaltyFeeAmount) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(
                    royaltyFeeAmount + platformFeeCut <= totalPrice,
                    "fees exceed the price"
                );
                royaltyRecipient = royaltyFeeRecipient;
                royaltyCut = royaltyFeeAmount;
            }
        } catch {}
        checkBalanceAndAllowance(
            msg.sender,
            target.paymentToken,
            totalPrice + platformFeeCut + royaltyCut
        );
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            PLATFORM_OWNER,
            platformFeeCut
        );
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            royaltyRecipient,
            royaltyCut
        );
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            target.creator,
            totalPrice
        );
        if (target.tokenType == TokenType.ERC1155) {
            IERC1155(target.tokenContract).safeTransferFrom(
                target.creator,
                msg.sender,
                target.tokenId,
                _quantity,
                ""
            );
        } else if (target.tokenType == TokenType.ERC721) {
            IERC721(target.tokenContract).safeTransferFrom(
                target.creator,
                msg.sender,
                target.tokenId
            );
        }
        // event
    }

    function bid(
        uint256 _listingId,
        address _bidder,
        uint256 _bidPrice,
        uint256 _quantity
    ) external {
        require(_bidder != address(0), "");
        require(_bidPrice != 0, "");
        require(_quantity != 0, "");
        Bid memory newBid = Bid(_listingId, _bidder, _bidPrice, _quantity);
        Bid[] memory bidsOfListing = bids[_listingId];
        Bid memory currentHighestBid = bidsOfListing[bidsOfListing.length];
        if (bidsOfListing.length > 0) {
            require(
                // include quantitiy
                (newBid.bid > currentHighestBid.bid &&
                    ((newBid.bid - currentHighestBid.bid) * MAX_BPS) /
                        currentHighestBid.bid >=
                    BID_BUFFER_BPS),
                ""
            );
        } else {
            require(newBid.bid >= Listings[_listingId].minBid);
        }
        bids[_listingId].push(newBid);
        // IERC20(Listings[_listingId].paymentToken).safeTransferFrom(msg.sender,address(this),)
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

    function checkBalanceAndAllowance(
        address checkAddress,
        address token,
        uint256 price
    ) internal view {
        require(
            price <= IERC20(token).balanceOf(checkAddress) &&
                price <= IERC20(token).allowance(checkAddress, address(this)),
            ""
        );
    }
}
