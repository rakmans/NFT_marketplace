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
    error listingDeleted();
    error listingEnded();
    // uint256 constant MAX_BPS = 10000;
    // uint256 constant BID_BUFFER_BPS = 500;
    uint256 PLATFORM_FEE;
    uint256 MAX_BPS;
    uint256 BID_BUFFER_BPS;
    address PLATFORM_OWNER;
    // address constant PLATFORM_OWNER =
    //     0x417C83C2674C85010A453a7496407B72E0a30ADF;
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
        bool deleted;
    }

    // listingId => bidder => bid bids;
    mapping(uint256 => Bid[]) public bids;
    mapping(address => bool) public deposited;

    Listing[] Listings;

    event CreatListing(
        uint256 indexed ListingId,
        address indexed Creator,
        address indexed TokenContract,
        uint256 TokenId,
        uint256 Quantity,
        bool Auction
    );

    event EditListing(
        uint256 indexed ListingId,
        address indexed Creator,
        address indexed TokenContract,
        uint256 TokenId,
        uint256 Quantity
    );

    modifier onlyCreator(uint256 _listingId) {
        address creator = Listings[_listingId].creator;
        if (msg.sender != creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }

    modifier mustNotDeleted(uint256 _listingId) {
        if (Listings[_listingId].deleted) {
            revert listingDeleted();
        }
        _;
    }

    modifier notEnded(uint256 _listingId) {
        if (Listings[_listingId].ended) {
            revert listingEnded();
        }
        _;
    }

    constructor(
        uint256 _maxBps,
        uint256 _bidBufferBps,
        uint256 _platformFee
    ) {
        PLATFORM_OWNER = msg.sender;
        PLATFORM_FEE = _platformFee;
        BID_BUFFER_BPS = _bidBufferBps;
        MAX_BPS = _maxBps;
    }

    function createList(
        address _tokenContract,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity,
        bool _isAuction
    ) external {
        require(_price != 0, "price != 0");
        require(_durationUntilEnd != 0, "duration != 0");
        require(_quantity != 0, "quantity != 0");
        address creator = msg.sender;
        TokenType tokenType = getTokenType(_tokenContract);
        _quantity = tokenType == TokenType.ERC721 ? 1 : _quantity;
        validateToken(_tokenContract, _tokenId, creator, _quantity, tokenType);
        if (_isAuction) {
            transferToken(
                _tokenContract,
                creator,
                address(this),
                _tokenId,
                _quantity,
                tokenType
            );
        }
        Listing memory newListing = Listing(
            Listings.length + 1,
            _tokenContract,
            _tokenId,
            tokenType,
            creator,
            _paymentToken,
            _price,
            block.timestamp,
            block.timestamp + _durationUntilEnd,
            _quantity,
            false,
            _isAuction,
            address(0),
            false
        );
        Listings.push(newListing);
        emit CreatListing(
            newListing.id,
            creator,
            _tokenContract,
            _tokenId,
            _quantity,
            _isAuction
        );
    }

    //not ended
    function editListing(
        uint256 _listingId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity
    )
        external
        onlyCreator(_listingId)
        mustNotDeleted(_listingId)
        notEnded(_listingId)
    {
        require(_price != 0, "");
        require(_durationUntilEnd != 0, "");
        require(_quantity != 0, "");
        Listing memory target = Listings[_listingId];
        if (target.tokenType == TokenType.ERC721) {
            _quantity = 1;
        }
        Listing memory newListing = Listing(
            _listingId,
            target.tokenContract,
            target.tokenId,
            target.tokenType,
            target.creator,
            _paymentToken,
            _price,
            target.start,
            block.timestamp + _durationUntilEnd,
            _quantity,
            target.isAuction,
            false,
            address(0),
            false
        );
        Listings[_listingId] = newListing;
        transferToken(
            target.tokenContract,
            address(this),
            target.creator,
            target.tokenId,
            target.quantity,
            target.tokenType
        );
        validateToken(
            target.tokenContract,
            target.tokenId,
            target.creator,
            _quantity,
            target.tokenType
        );
        transferToken(
            target.tokenContract,
            target.creator,
            address(this),
            target.tokenId,
            _quantity,
            target.tokenType
        );
        emit EditListing(
            _listingId,
            target.creator,
            target.tokenContract,
            target.tokenId,
            target.quantity
        );
    }

    // //not ended
    // function cancelListing(uint256 _listingId)
    //     external
    //     onlyCreator(_listingId)
    //     mustNotDeleted(_listingId)
    //     notEnded(_listingId)
    // {
    //     Listing memory target = Listings[_listingId];
    //     target.deleted = true;
    //     if (target.isAuction) {
    //         if (target.tokenType == TokenType.ERC1155) {
    //             IERC1155(target.tokenContract).safeTransferFrom(
    //                 address(this),
    //                 target.creator,
    //                 target.tokenId,
    //                 target.quantity,
    //                 ""
    //             );
    //         } else {
    //             IERC721(target.tokenContract).safeTransferFrom(
    //                 address(this),
    //                 target.creator,
    //                 target.tokenId
    //             );
    //         }
    //     }
    //     Listings[_listingId] = target;
    //     // event
    // }

    //not ended
    function buy(uint256 _listingId, uint256 _quantity)
        external
        mustNotDeleted(_listingId)
        notEnded(_listingId)
    {
        Listing memory target = Listings[_listingId];
        uint256 totalPrice = target.price * _quantity;
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
        if (royaltyCut != 0 && royaltyRecipient != address(0)) {
            IERC20(target.paymentToken).safeTransferFrom(
                msg.sender,
                royaltyRecipient,
                royaltyCut
            );
        }
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            target.creator,
            totalPrice
        );
        transferToken(
            target.tokenContract,
            target.creator,
            msg.sender,
            target.tokenId,
            _quantity,
            target.tokenType
        );
        // event
    }

    function bid(uint256 _listingId, uint256 _bidPrice) external {
        require(msg.sender != address(0), "");
        require(_bidPrice != 0, "");
        Listing memory target = Listings[_listingId];
        Bid memory newBid = Bid(_listingId, msg.sender, _bidPrice);
        Bid[] memory bidsOfListing = bids[_listingId];
        Bid memory currentHighestBid = bidsOfListing[bidsOfListing.length];
        uint256 newBidPrice = newBid.bid;
        uint256 currentBidPrice = currentHighestBid.bid;
        if (bidsOfListing.length > 0) {
            require(
                (newBidPrice > currentBidPrice &&
                    ((newBidPrice - currentBidPrice) * MAX_BPS) /
                        currentBidPrice >=
                    BID_BUFFER_BPS),
                ""
            );
        } else {
            require(newBidPrice >= target.price);
        }
        bids[_listingId].push(newBid);
        target.highestBidder = msg.sender;
        Listings[_listingId] = target;
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            newBidPrice * target.quantity
        );
        // event
    }

    function closeAuction(uint256 _listingId) external {
        Listing memory target = Listings[_listingId];
        require(target.isAuction, "");
        require(!target.ended, "");
        require(block.timestamp > target.end, "");
        target.ended = true;
        Listings[_listingId] = target;
        Bid[] memory listingBids = bids[_listingId];
        Bid memory highestBid = listingBids[listingBids.length];
        require(highestBid.bidder != address(0), "");
        uint256 totalPrice = highestBid.bid * target.quantity;
        // highestBid.bidder == target.highestBidder
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
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            PLATFORM_OWNER,
            platformFeeCut
        );
        if (royaltyCut != 0 && royaltyRecipient != address(0)) {
            IERC20(target.paymentToken).safeTransferFrom(
                msg.sender,
                royaltyRecipient,
                royaltyCut
            );
        }
        IERC20(target.paymentToken).safeTransferFrom(
            msg.sender,
            target.creator,
            totalPrice
        );
        if (target.tokenType == TokenType.ERC721) {
            IERC721(target.tokenContract).safeTransferFrom(
                address(this),
                target.highestBidder,
                target.tokenId
            );
        } else {
            IERC1155(target.tokenContract).safeTransferFrom(
                address(this),
                target.highestBidder,
                target.tokenId,
                target.quantity,
                ""
            );
        }
        // event
    }

    function transferToken(
        address _tokenContract,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _quantity,
        TokenType _tokenType
    ) internal {
        if (_tokenType == TokenType.ERC721) {
            IERC721(_tokenContract).safeTransferFrom(_from, _to, _tokenId);
        } else {
            IERC1155(_tokenContract).safeTransferFrom(
                _from,
                _to,
                _tokenId,
                _quantity,
                ""
            );
        }
    }

    function getRoyalty(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _totalPrice,
        uint256 _platformFeeCut
    ) internal view returns (address royaltyRecipient, uint256 royaltyCut) {
        try
            IERC2981(_tokenContract).royaltyInfo(_tokenId, _totalPrice)
        returns (address royaltyFeeRecipient, uint256 royaltyFeeAmount) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(
                    royaltyFeeAmount + _platformFeeCut <= _totalPrice,
                    "fees exceed the price"
                );
                return (royaltyFeeRecipient, royaltyFeeAmount);
            }
        } catch {}
    }

    function getListing(uint256 listingId)
        external
        view
        returns (Listing memory)
    {
        return (Listings[listingId]);
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
