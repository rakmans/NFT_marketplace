// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

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
    mapping(uint256 => mapping(address => Bid)) public bidsMap;

    /**
     * @dev Array of listings
     */
    Listing[] listings;

    /**
     * @dev Event emitted when a listing is created
     */
    event CreatListingLog(
        uint256 indexed listingId,
        address indexed creator,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 quantity,
        bool auction
    );
    /**
     * @dev Event emitted when a listing is edited
     */
    event EditListingLog(
        uint256 indexed listingId,
        address indexed creator,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 quantity
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
    event CloseAuctionLog(
        uint256 indexed listingId,
        address indexed highestBidder,
        uint256 quantity,
        uint256 price
    );
    /**
     * @dev Event emitted when an auction is canceld
     */
    event CancelAuctionLog(uint256 indexed listingId);
    /**
     * @dev Event emitted when a bid is placed
     */
    event BidLog(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 bidPrice,
        uint256 quntity
    );

    event OfferLog(
        uint256 indexed listingId,
        address indexed offeror,
        uint256 offerPrice
    );

    /**
     * @dev Event emitted when the user withdraws her money
     */
    event Withdrawn(
        uint256 indexed listingId,
        address indexed harvester,
        uint256 value
    );

    error onlyCreatorCanCall();
    error listingDeleted();
    error listingEnded();

    /**
     * @dev Error thrown when only the creator can call a function
     */
    modifier onlyCreator(uint256 listingId) {
        if (msg.sender != listings[listingId].creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing has ended
     */
    modifier notEnded(uint256 listingId) {
        if (listings[listingId].ended) {
            revert listingEnded();
        }
        _;
    }

    constructor(
        uint256 bidBufferBps,
        uint256 timeBuffer,
        uint256 platformFee,
        uint256 maxBps
    ) {
        PLATFORM_OWNER = msg.sender;
        PLATFORM_FEE = platformFee;
        BID_BUFFER_BPS = bidBufferBps;
        MAX_BPS = maxBps;
        TIME_BUFFER = timeBuffer;
    }

    /**
     * @dev Creates a new listing.
     * @param tokenContract Address of the token contract
     * @param tokenId Token ID
     * @param paymentToken Address of the payment token
     * @param price Listing price
     * @param durationUntilEnd Duration of the listing until it ends
     * @param quantity Quantity available for sale
     * @param isAuction Flag indicating if the listing is an auction
     */
    function createList(
        address tokenContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 durationUntilEnd,
        uint256 quantity,
        bool isAuction
    ) external {
        require(price != 0, "price != 0");
        require(durationUntilEnd != 0, "duration != 0");
        require(quantity != 0, "quantity != 0");
        require(paymentToken != address(0), "");
        address creator = msg.sender;
        TokenType tokenType = getTokenType(tokenContract);
        quantity = tokenType == TokenType.ERC721 ? 1 : quantity;
        validateToken(tokenContract, tokenId, creator, quantity, tokenType);
        if (isAuction) {
            transferToken(
                tokenContract,
                creator,
                address(this),
                tokenId,
                quantity,
                tokenType
            );
        }
        Listing memory newListing = Listing(
            listings.length,
            tokenContract,
            tokenId,
            tokenType,
            creator,
            paymentToken,
            price,
            block.timestamp,
            block.timestamp + durationUntilEnd,
            quantity,
            false,
            isAuction
        );
        listings.push(newListing);
        emit CreatListingLog(
            newListing.id,
            creator,
            tokenContract,
            tokenId,
            quantity,
            isAuction
        );
    }

    /**
     * @dev Edits an existing listing.
     * @param listingId Unique identifier of the listing
     * @param paymentToken Address of the payment token
     * @param price New listing price
     * @param durationUntilEnd New duration for the listing until it ends
     * @param quantity New quantity available for sale
     */
    function editListing(
        uint256 listingId,
        address paymentToken,
        uint256 price,
        uint256 durationUntilEnd,
        uint256 quantity
    ) external onlyCreator(listingId) {
        require(price != 0, "");
        require(durationUntilEnd != 0, "");
        require(quantity != 0, "");
        require(paymentToken != address(0), "");
        Listing memory targetListing = listings[listingId];
        if (targetListing.tokenType == TokenType.ERC721) {
            quantity = 1;
        }
        if (targetListing.isAuction) {
            price = targetListing.price;
        }
        Listing memory newListing = Listing(
            listingId,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.tokenType,
            targetListing.creator,
            paymentToken,
            price,
            targetListing.start,
            block.timestamp + durationUntilEnd,
            quantity,
            targetListing.isAuction,
            false
        );
        listings[listingId] = newListing;
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
                quantity,
                targetListing.tokenType
            );
            transferToken(
                targetListing.tokenContract,
                targetListing.creator,
                address(this),
                targetListing.tokenId,
                quantity,
                targetListing.tokenType
            );
        }
        emit EditListingLog(
            listingId,
            targetListing.creator,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.quantity
        );
    }

    /**
     * @dev Allows a user to purchase tokens from a listing.
     * @param listingId Unique identifier of the listing
     * @param quantity Quantity of tokens to purchase
     */
    function buy(
        uint256 listingId,
        uint256 quantity
    ) external notEnded(listingId) {
        Listing memory targetListing = listings[listingId];
        uint256 totalPrice = targetListing.price * quantity;
        targetListing.quantity -= quantity;
        targetListing.ended = targetListing.quantity == 0;
        listings[listingId] = targetListing;
        uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
        (address royaltyRecipient, uint256 royaltyCut) = getRoyalty(
            targetListing.tokenContract,
            targetListing.tokenId,
            totalPrice,
            platformFeeCut
        );
        payout(
            msg.sender,
            targetListing.creator,
            totalPrice,
            platformFeeCut,
            royaltyCut,
            royaltyRecipient,
            targetListing.paymentToken
        );
        transferToken(
            targetListing.tokenContract,
            targetListing.creator,
            msg.sender,
            targetListing.tokenId,
            quantity,
            targetListing.tokenType
        );
        emit BuyLog(listingId, msg.sender, quantity, targetListing.price);
    }

    /**
     * @dev Allows a user to place a bid on a listing.
     * @param listingId Unique identifier of the listing
     * @param bidPrice Bid price in the payment token
     */
    function bid(
        uint256 listingId,
        uint256 bidPrice,
        uint256 quantity
    ) external {
        require(msg.sender != address(0), "");
        require(bidPrice != 0, "");
        require(quantity != 0, "");
        Listing memory targetListing = listings[listingId];
        require(block.timestamp < targetListing.end, "");
        if (targetListing.tokenType == TokenType.ERC721) {
            quantity = 1;
        }
        Bid memory lastBid = bidsMap[listingId][msg.sender];
        Bid memory newBid = Bid(msg.sender, bidPrice, quantity);
        Bid[] memory bidsOfListing = bids[listingId];
        uint256 newBidPrice = newBid.bid;
        uint256 totalBidPrice = newBid.bid * newBid.quantity;
        if (bidsOfListing.length > 0) {
            Bid memory currentHighestBid = bidsOfListing[
                bidsOfListing.length - 1
            ];
            uint256 currentBidPrice = currentHighestBid.bid *
                currentHighestBid.quantity;
            require(
                (totalBidPrice > currentBidPrice &&
                    ((totalBidPrice - currentBidPrice) * MAX_BPS) /
                        currentBidPrice >=
                    BID_BUFFER_BPS),
                ""
            );
        } else {
            require(newBidPrice >= targetListing.price, "");
        }
        IERC20(targetListing.paymentToken).safeTransfer(
            msg.sender,
            lastBid.bid * lastBid.quantity
        );
        bids[listingId].push(newBid);
        bidsMap[listingId][msg.sender] = newBid;
        if (targetListing.end - block.timestamp <= TIME_BUFFER) {
            targetListing.end += TIME_BUFFER;
        }
        listings[listingId] = targetListing;
        checkBalanceAndAllowance(
            msg.sender,
            targetListing.paymentToken,
            bidPrice * quantity
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            bidPrice * quantity
        );
        emit BidLog(listingId, msg.sender, newBidPrice, quantity);
    }

    /**
     * @dev Allows the creator to close an auction listing.
     * @param listingId Unique identifier of the listing
     */
    function closeAuction(uint256 listingId) external {
        Listing memory targetListing = listings[listingId];
        require(targetListing.isAuction, "");
        require(!targetListing.ended, "");
        require(block.timestamp > targetListing.end, "");
        targetListing.ended = true;
        listings[listingId] = targetListing;
        Bid[] memory listingBids = bids[listingId];
        if (listingBids.length == 0) {
            transferToken(
                targetListing.tokenContract,
                address(this),
                targetListing.creator,
                targetListing.tokenId,
                targetListing.quantity,
                targetListing.tokenType
            );
            emit CancelAuctionLog(listingId);
        } else {
            Bid memory highestBid = listingBids[listingBids.length - 1];
            bidsMap[listingId][highestBid.bidder] = Bid(
                highestBid.bidder,
                0,
                0
            );
            uint256 totalPrice = highestBid.bid * highestBid.quantity;
            uint256 platformFeeCut = (totalPrice * PLATFORM_FEE) / MAX_BPS;
            (address royaltyRecipient, uint256 royaltyCut) = getRoyalty(
                targetListing.tokenContract,
                targetListing.tokenId,
                totalPrice,
                platformFeeCut
            );
            payout(
                address(this),
                targetListing.creator,
                totalPrice,
                platformFeeCut,
                royaltyCut,
                royaltyRecipient,
                targetListing.paymentToken
            );
            transferToken(
                targetListing.tokenContract,
                address(this),
                highestBid.bidder,
                targetListing.tokenId,
                highestBid.quantity,
                targetListing.tokenType
            );
            if (targetListing.quantity - highestBid.quantity > 0) {
                transferToken(
                    targetListing.tokenContract,
                    address(this),
                    targetListing.creator,
                    targetListing.tokenId,
                    targetListing.quantity - highestBid.quantity,
                    targetListing.tokenType
                );
            }
            emit CloseAuctionLog(
                listingId,
                highestBid.bidder,
                highestBid.quantity,
                highestBid.bid
            );
        }
    }

    /**
     * @dev Withdraws the user's bid from a listing.
     * @param listingId The ID of the listing.
     */
    function withdrawal(uint256 listingId) external {
        require(listings[listingId].ended, "");
        require(listings[listingId].isAuction, "");
        Bid memory userBal = bidsMap[listingId][msg.sender];
        require(userBal.bid > 0 && userBal.quantity > 0, "");
        bidsMap[listingId][msg.sender] = Bid(userBal.bidder, 0, 0);
        IERC20(listings[listingId].paymentToken).safeTransfer(
            msg.sender,
            userBal.bid * userBal.quantity
        );
        emit Withdrawn(listingId, msg.sender, userBal.bid * userBal.quantity);
    }

    /**
     * @dev Internal function to transfer tokens (NFTs or ERC20) from one address to another.
     * @param tokenContract Address of the token contract
     * @param from Address from which tokens are transferred
     * @param to Address to which tokens are transferred
     * @param tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param quantity Quantity of tokens (for ERC1155, set to 1 for ERC721)
     * @param tokenType Type of token (ERC721 or ERC1155)
     */
    function transferToken(
        address tokenContract,
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity,
        TokenType tokenType
    ) internal {
        if (tokenType == TokenType.ERC721) {
            IERC721(tokenContract).safeTransferFrom(from, to, tokenId);
        } else {
            IERC1155(tokenContract).safeTransferFrom(
                from,
                to,
                tokenId,
                quantity,
                ""
            );
        }
    }

    function payout(
        address from,
        address to,
        uint256 amount,
        uint256 platformFeeCut,
        uint256 royaltyCut,
        address royaltyRecipient,
        address paymentToken
    ) internal {
        if (from == address(this)) {
            IERC20(paymentToken).safeTransfer(PLATFORM_OWNER, platformFeeCut);
            if (royaltyCut != 0 && royaltyRecipient != address(0)) {
                IERC20(paymentToken).safeTransfer(royaltyRecipient, royaltyCut);
            }
            IERC20(paymentToken).safeTransfer(
                to,
                amount - (platformFeeCut + royaltyCut)
            );
        } else {
            checkBalanceAndAllowance(from, paymentToken, amount);
            IERC20(paymentToken).safeTransferFrom(
                from,
                PLATFORM_OWNER,
                platformFeeCut
            );
            if (royaltyCut != 0 && royaltyRecipient != address(0)) {
                IERC20(paymentToken).safeTransferFrom(
                    from,
                    royaltyRecipient,
                    royaltyCut
                );
            }
            IERC20(paymentToken).safeTransferFrom(
                from,
                to,
                amount - (platformFeeCut + royaltyCut)
            );
        }
    }

    /**
     * @dev Internal function to retrieve royalty information for a given token.
     * @param tokenContract Address of the token contract
     * @param tokenId Token ID
     * @param totalPrice Total price of the transaction
     * @param platformFeeCut Platform fee cut
     * @return royaltyRecipient Address of the royalty recipient
     * @return royaltyCut Amount of royalty
     */
    function getRoyalty(
        address tokenContract,
        uint256 tokenId,
        uint256 totalPrice,
        uint256 platformFeeCut
    ) internal view returns (address royaltyRecipient, uint256 royaltyCut) {
        try IERC2981(tokenContract).royaltyInfo(tokenId, totalPrice) returns (
            address royaltyFeeRecipient,
            uint256 royaltyFeeAmount
        ) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(
                    royaltyFeeAmount + platformFeeCut <= totalPrice,
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

    function getUserBidBalance(
        uint256 listingId,
        address userAddress
    ) external view returns (Bid memory) {
        return (bidsMap[listingId][userAddress]);
    }

    /**
     * @dev Internal function to determine the type of a token (ERC721 or ERC1155).
     * @param contractAddress Address of the token contract
     * @return tokenType Type of token (ERC721 or ERC1155)
     */ function getTokenType(
        address contractAddress
    ) internal view returns (TokenType tokenType) {
        if (
            IERC165(contractAddress).supportsInterface(
                type(IERC1155).interfaceId
            )
        ) {
            tokenType = TokenType.ERC1155;
        } else if (
            IERC165(contractAddress).supportsInterface(
                type(IERC721).interfaceId
            )
        ) {
            tokenType = TokenType.ERC721;
        } else {
            revert("token must be ERC1155 or ERC721.");
        }
    }

    /**
     * @dev Internal function to validate token ownership and approval.
     * @param token Address of the token contract
     * @param tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param owner Expected owner address
     * @param quantity Quantity of tokens (for ERC1155, set to 1 for ERC721)
     * @param tokenType Type of token (ERC721 or ERC1155)
     */
    function validateToken(
        address token,
        uint256 tokenId,
        address owner,
        uint256 quantity,
        TokenType tokenType
    ) internal view {
        if (tokenType == TokenType.ERC721) {
            IERC721 token721 = IERC721(token);
            require(owner == token721.ownerOf(tokenId), "");
            address approved = token721.getApproved(tokenId);
            require(approved == address(this), "");
        } else {
            IERC1155 token1155 = IERC1155(token);
            uint256 balanceOf = token1155.balanceOf(owner, tokenId);
            require(quantity <= balanceOf, "");
            bool isApprove = token1155.isApprovedForAll(owner, address(this));
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
