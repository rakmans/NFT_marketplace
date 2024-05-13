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

/**
 * @title NftMarketplace
 * @author Rakmans
 * @notice A marketplace for buying and selling NFTs
 */
contract NftMarketplace is ERC1155Holder, ERC721Holder {
    using SafeERC20 for IERC20;

    /**
     * @dev Enum for token types
     */
    enum TokenType {
        ERC1155,
        ERC721
    }
    /**
     * @dev Enum for listing types
     */
    enum ListingType {
        Sale,
        Auction
    }
    /**
     * @dev Struct for bids
     */
    struct Bid {
        address bidder;
        uint256 bid;
    }
    /**
     * @dev Struct for offers
     */
    struct Offer {
        uint256 id;
        address offeror;
        uint256 listingId;
        uint256 price;
        uint256 quantity;
    }
    /**
     * @dev Struct for listings
     */
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

    /**
     * @dev Platform fee
     */
    uint256 PLATFORM_FEE;
    /**
     * @dev Maximum basis points
     */
    uint256 MAX_BPS;
    /**
     * @dev Bid buffer basis points
     */
    uint256 BID_BUFFER_BPS;
    /**
     * @dev Platform owner
     */
    address PLATFORM_OWNER;
    /**
     * @dev Time buffer
     */
    uint256 TIME_BUFFER;

    /**
     * @dev Mapping of listing ID to bids
     */
    mapping(uint256 => Bid[]) public bids;
    mapping(uint256 => mapping(address => uint256)) public bidsMap;
    /**
     * @dev Mapping of listing ID to offers
     */
    mapping(uint256 => Offer[]) public offers;

    /**
     * @dev Array of listings
     */
    Listing[] listings;

    /**
     * @dev Event emitted when a listing is created
     */
    event CreatListingLog(
        uint256 indexed ListingId,
        address indexed Creator,
        address indexed TokenContract,
        uint256 TokenId,
        uint256 Quantity,
        bool Auction
    );
    /**
     * @dev Event emitted when a listing is edited
     */
    event EditListingLog(
        uint256 indexed ListingId,
        address indexed Creator,
        address indexed TokenContract,
        uint256 TokenId,
        uint256 Quantity
    );
    /**
     * @dev Event emitted when a listing is bought
     */
    event BuyLog(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 quantity,
        uint256 price
    );
    /**
     * @dev Event emitted when an auction is closed
     */
    event CloseAuctionLog(uint256 indexed listingId);
    /**
     * @dev Event emitted when a bid is placed
     */
    event BidLog(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 bid
    );

    error onlyCreatorCanCall();
    error listingDeleted();
    error listingEnded();
    /**
     * @dev Error thrown when only the creator can call a function
     */
    modifier onlyCreator(uint256 _listingId) {
        address creator = listings[_listingId].creator;
        if (msg.sender != creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing is deleted
     */
    modifier mustNotDeleted(uint256 _listingId) {
        if (listings[_listingId].deleted) {
            revert listingDeleted();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing has ended
     */
    modifier notEnded(uint256 _listingId) {
        if (listings[_listingId].ended) {
            revert listingEnded();
        }
        _;
    }

    constructor(
        uint256 _bidBufferBps,
        uint256 timeBuffer,
        uint256 _platformFee,
        uint256 _maxBps
    ) {
        PLATFORM_OWNER = msg.sender;
        PLATFORM_FEE = _platformFee;
        BID_BUFFER_BPS = _bidBufferBps;
        MAX_BPS = _maxBps;
        TIME_BUFFER = timeBuffer;
    }

    /**
     * @dev Creates a new listing.
     * @param _tokenContract Address of the token contract
     * @param _tokenId Token ID
     * @param _paymentToken Address of the payment token
     * @param _price Listing price
     * @param _durationUntilEnd Duration of the listing until it ends
     * @param _quantity Quantity available for sale
     * @param _isAuction Flag indicating if the listing is an auction
     */
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
            listings.length,
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
        listings.push(newListing);
        emit CreatListingLog(
            newListing.id,
            creator,
            _tokenContract,
            _tokenId,
            _quantity,
            _isAuction
        );
    }

    /**
     * @dev Edits an existing listing.
     * @param _listingId Unique identifier of the listing
     * @param _paymentToken Address of the payment token
     * @param _price New listing price
     * @param _durationUntilEnd New duration for the listing until it ends
     * @param _quantity New quantity available for sale
     */
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
        Listing memory targetListing = listings[_listingId];
        if (targetListing.tokenType == TokenType.ERC721) {
            _quantity = 1;
        }
        Listing memory newListing = Listing(
            _listingId,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.tokenType,
            targetListing.creator,
            _paymentToken,
            _price,
            targetListing.start,
            block.timestamp + _durationUntilEnd,
            _quantity,
            targetListing.isAuction,
            false,
            address(0),
            false
        );
        listings[_listingId] = newListing;
        if (targetListing.isAuction) {
            transferToken(
                targetListing.tokenContract,
                address(this),
                targetListing.creator,
                targetListing.tokenId,
                targetListing.quantity,
                targetListing.tokenType
            );
            validateToken(
                targetListing.tokenContract,
                targetListing.tokenId,
                targetListing.creator,
                _quantity,
                targetListing.tokenType
            );
            transferToken(
                targetListing.tokenContract,
                targetListing.creator,
                address(this),
                targetListing.tokenId,
                _quantity,
                targetListing.tokenType
            );
        }
        emit EditListingLog(
            _listingId,
            targetListing.creator,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.quantity
        );
    }

    // //not ended
    // function cancelListing(uint256 _listingId)
    //     external
    //     onlyCreator(_listingId)
    //     mustNotDeleted(_listingId)
    //     notEnded(_listingId)
    // {
    //     Listing memory targetListing = listings[_listingId];
    //     targetListing.deleted = true;
    //     if (targetListing.isAuction) {
    //         if (targetListing.tokenType == TokenType.ERC1155) {
    //             IERC1155(targetListing.tokenContract).safeTransferFrom(
    //                 address(this),
    //                 targetListing.creator,
    //                 targetListing.tokenId,
    //                 targetListing.quantity,
    //                 ""
    //             );
    //         } else {
    //             IERC721(targetListing.tokenContract).safeTransferFrom(
    //                 address(this),
    //                 targetListing.creator,
    //                 targetListing.tokenId
    //             );
    //         }
    //     }
    //     listings[_listingId] = targetListing;
    //     // event
    // }
    /**
     * @dev Allows a user to purchase tokens from a listing.
     * @param _listingId Unique identifier of the listing
     * @param _quantity Quantity of tokens to purchase
     */
    function buy(
        uint256 _listingId,
        uint256 _quantity
    ) external mustNotDeleted(_listingId) notEnded(_listingId) {
        Listing memory targetListing = listings[_listingId];
        uint256 totalPrice = targetListing.price * _quantity;
        targetListing.quantity -= _quantity;
        targetListing.ended = targetListing.quantity == 0;
        listings[_listingId] = targetListing;
        uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
        (address royaltyRecipient, uint256 royaltyCut) = getRoyalty(
            targetListing.tokenContract,
            targetListing.tokenId,
            totalPrice,
            platformFeeCut
        );
        checkBalanceAndAllowance(
            msg.sender,
            targetListing.paymentToken,
            totalPrice
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            PLATFORM_OWNER,
            platformFeeCut
        );
        if (royaltyCut != 0 && royaltyRecipient != address(0)) {
            IERC20(targetListing.paymentToken).safeTransferFrom(
                msg.sender,
                royaltyRecipient,
                royaltyCut
            );
        }
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            targetListing.creator,
            totalPrice - (platformFeeCut + royaltyCut)
        );
        transferToken(
            targetListing.tokenContract,
            targetListing.creator,
            msg.sender,
            targetListing.tokenId,
            _quantity,
            targetListing.tokenType
        );
        emit BuyLog(_listingId, msg.sender, _quantity, targetListing.price);
    }

    /**
     * @dev Allows a user to place a bid on a listing.
     * @param _listingId Unique identifier of the listing
     * @param _bidPrice Bid price in the payment token
     */
    function bid(uint256 _listingId, uint256 _bidPrice) external {
        require(msg.sender != address(0), "");
        require(_bidPrice != 0, "");
        Listing memory targetListing = listings[_listingId];
        uint256 lastBid = bidsMap[_listingId][msg.sender];
        Bid memory newBid = Bid(msg.sender, _bidPrice + lastBid);
        Bid[] memory bidsOfListing = bids[_listingId];
        uint256 newBidPrice = newBid.bid;
        if (bidsOfListing.length > 0) {
            Bid memory currentHighestBid = bidsOfListing[
                bidsOfListing.length - 1
            ];
            uint256 currentBidPrice = currentHighestBid.bid;
            require(
                (newBidPrice + lastBid > currentBidPrice &&
                    ((newBidPrice + lastBid - currentBidPrice) * MAX_BPS) /
                        currentBidPrice >=
                    BID_BUFFER_BPS),
                ""
            );
        } else {
            require(newBidPrice >= targetListing.price, "");
        }
        bids[_listingId].push(newBid);
        bidsMap[_listingId][msg.sender] = _bidPrice + lastBid;
        targetListing.highestBidder = msg.sender;
        targetListing.end = targetListing.end + 15 minutes;
        listings[_listingId] = targetListing;
        checkBalanceAndAllowance(
            msg.sender,
            targetListing.paymentToken,
            _bidPrice * targetListing.quantity
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            _bidPrice * targetListing.quantity
        );
        emit BidLog(_listingId, msg.sender, newBidPrice + lastBid);
    }

    /**
     * @dev Allows a user to make an offer on a fixed-price listing.
     * @param _listingId Unique identifier of the listing
     * @param _price Offer price in the payment token
     * @param _quantity Quantity of tokens being offered
     */
    function offer(
        uint256 _listingId,
        uint256 _price,
        uint256 _quantity
    ) external {
        Listing memory targetListing = listings[_listingId];
        require(!targetListing.isAuction, "");
        Offer[] memory listingOffers = offers[_listingId];
        if (listingOffers.length > 0) {
            Offer memory lastOffer = listingOffers[listingOffers.length - 1];
            require(_price > lastOffer.price, "");
        } else {
            require(_price < targetListing.price, "");
        }
        Offer memory newOffer = Offer(
            listingOffers.length,
            msg.sender,
            _listingId,
            _price,
            _quantity
        );
        offers[_listingId].push(newOffer);
    }

    /**
     * @dev Allows the creator to accept an offer on a fixed-price listing.
     * @param _listingId Unique identifier of the listing
     * @param _offerId Unique identifier of the offer
     */
    function acceptOffer(
        uint256 _listingId,
        uint256 _offerId
    ) external onlyCreator(_listingId) {
        Listing memory targetListing = listings[_listingId];
        Offer memory targetOffer = offers[_listingId][_offerId];
        uint256 totalPrice = targetOffer.price * targetOffer.quantity;
        targetListing.quantity -= targetOffer.quantity;
        targetListing.ended = targetListing.quantity == 0;
        listings[_listingId] = targetListing;
        uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
        (address royaltyRecipient, uint256 royaltyCut) = getRoyalty(
            targetListing.tokenContract,
            targetListing.tokenId,
            totalPrice,
            platformFeeCut
        );
        checkBalanceAndAllowance(
            msg.sender,
            targetListing.paymentToken,
            totalPrice + platformFeeCut + royaltyCut
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            PLATFORM_OWNER,
            platformFeeCut
        );
        if (royaltyCut != 0 && royaltyRecipient != address(0)) {
            IERC20(targetListing.paymentToken).safeTransferFrom(
                msg.sender,
                royaltyRecipient,
                royaltyCut
            );
        }
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            targetListing.creator,
            totalPrice
        );
        transferToken(
            targetListing.tokenContract,
            targetListing.creator,
            msg.sender,
            targetListing.tokenId,
            targetOffer.quantity,
            targetListing.tokenType
        );
        emit BuyLog(
            _listingId,
            msg.sender,
            targetOffer.quantity,
            targetOffer.price
        );
    }

    /**
     * @dev Allows the creator to close an auction listing.
     * @param _listingId Unique identifier of the listing
     */
    function closeAuction(uint256 _listingId) external {
        Listing memory targetListing = listings[_listingId];
        require(targetListing.isAuction, "");
        require(!targetListing.ended, "");
        require(block.timestamp > targetListing.end, "");
        targetListing.ended = true;
        listings[_listingId] = targetListing;
        Bid[] memory listingBids = bids[_listingId];
        Bid memory highestBid = listingBids[listingBids.length];
        require(highestBid.bidder != address(0), "");
        uint256 totalPrice = highestBid.bid * targetListing.quantity;
        uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
        (address royaltyRecipient, uint256 royaltyCut) = getRoyalty(
            targetListing.tokenContract,
            targetListing.tokenId,
            totalPrice,
            platformFeeCut
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            PLATFORM_OWNER,
            platformFeeCut
        );
        if (royaltyCut != 0 && royaltyRecipient != address(0)) {
            IERC20(targetListing.paymentToken).safeTransferFrom(
                msg.sender,
                royaltyRecipient,
                royaltyCut
            );
        }
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            targetListing.creator,
            totalPrice
        );
        transferToken(
            targetListing.tokenContract,
            address(this),
            targetListing.highestBidder,
            targetListing.tokenId,
            targetListing.quantity,
            targetListing.tokenType
        );
        emit CloseAuctionLog(_listingId);
    }

    /**
     * @dev Internal function to transfer tokens (NFTs or ERC20) from one address to another.
     * @param _tokenContract Address of the token contract
     * @param _from Address from which tokens are transferred
     * @param _to Address to which tokens are transferred
     * @param _tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param _quantity Quantity of tokens (for ERC1155, set to 1 for ERC721)
     * @param _tokenType Type of token (ERC721 or ERC1155)
     */
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

    /**
     * @dev Internal function to retrieve royalty information for a given token.
     * @param _tokenContract Address of the token contract
     * @param _tokenId Token ID
     * @param _totalPrice Total price of the transaction
     * @param _platformFeeCut Platform fee cut
     * @return royaltyRecipient Address of the royalty recipient
     * @return royaltyCut Amount of royalty
     */
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

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return (listings[listingId]);
    }

    function getListingBids(
        uint256 listingId
    ) external view returns (Bid[] memory) {
        return (bids[listingId]);
    }

    /**
     * @dev Internal function to determine the type of a token (ERC721 or ERC1155).
     * @param _assetContract Address of the token contract
     * @return tokenType Type of token (ERC721 or ERC1155)
     */ function getTokenType(
        address _assetContract
    ) internal view returns (TokenType tokenType) {
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

    /**
     * @dev Internal function to validate token ownership and approval.
     * @param _token Address of the token contract
     * @param _tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param _owner Expected owner address
     * @param _quantity Quantity of tokens (for ERC1155, set to 1 for ERC721)
     * @param _tokenType Type of token (ERC721 or ERC1155)
     */
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

    /**
     * @dev Internal function to check user's balance and allowance for a payment token.
     * @param checkAddress Address to check
     * @param token Address of the payment token
     * @param price Total price of the transaction
     */
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
