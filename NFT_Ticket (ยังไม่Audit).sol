// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFT_Ticket is ERC721, Ownable {
    using Strings for uint256;

    uint256 public nextTokenId = 1;
    uint256 public resaleLimitPercent = 20;
    uint256 public resaleLimitCount = 3;
    string public baseTokenURI;

    struct TicketInfo {
        uint256 originalPrice;
        uint256 resaleCount;
        uint256 mintedAt;
        uint256 lastSalePrice;
    }

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => TicketInfo) public ticketInfo;
    mapping(uint256 => Listing) public listings;
    uint256[] public listedTokenIds;
    mapping(uint256 => uint256) private previousLastSalePrice;

    constructor(string memory _baseTokenURI) ERC721("NFT_Ticket", "TTT") Ownable(msg.sender) {
        baseTokenURI = _baseTokenURI;
    }

    // -------------------------------
    // Metadata
    // -------------------------------

    function setBaseURI(string memory _uri) external onlyOwner {
        baseTokenURI = _uri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return string(abi.encodePacked(baseTokenURI, tokenId.toString(), ".json"));
    }

    // -------------------------------
    // Minting and Listing
    // -------------------------------

    function mintAndListTickets(
        address to,
        uint256[] memory prices,
        uint256[] memory listingPrices
    ) external onlyOwner {
        require(prices.length == listingPrices.length, "Mismatched arrays");

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 tokenId = nextTokenId;
            _safeMint(to, tokenId);

            ticketInfo[tokenId] = TicketInfo({
                originalPrice: prices[i],
                resaleCount: 0,
                mintedAt: block.timestamp,
                lastSalePrice: 0
            });

            uint256 basePrice = prices[i];
            uint256 maxResalePrice = basePrice + (basePrice * resaleLimitPercent) / 100;
            require(listingPrices[i] <= maxResalePrice, "Listing price exceeds resale cap");

            listings[tokenId] = Listing({ seller: to, price: listingPrices[i] });
            listedTokenIds.push(tokenId);
            previousLastSalePrice[tokenId] = 0;
            ticketInfo[tokenId].lastSalePrice = listingPrices[i];

            nextTokenId++;
        }
    }

    function listTicket(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        TicketInfo storage info = ticketInfo[tokenId];
        uint256 basePrice = info.lastSalePrice > 0 ? info.lastSalePrice : info.originalPrice;
        uint256 maxResalePrice = basePrice + (basePrice * resaleLimitPercent) / 100;

        require(price <= maxResalePrice, "Listing price exceeds resale cap");
        require(info.resaleCount < resaleLimitCount, "Resale limit exceeded");

        listings[tokenId] = Listing({ seller: msg.sender, price: price });
        listedTokenIds.push(tokenId);
        previousLastSalePrice[tokenId] = info.lastSalePrice;
        info.lastSalePrice = price;
    }

    function cancelListing(uint256 tokenId) external {
        require(listings[tokenId].seller == msg.sender, "Not seller");

        ticketInfo[tokenId].lastSalePrice = previousLastSalePrice[tokenId];
        delete previousLastSalePrice[tokenId];
        delete listings[tokenId];

        for (uint i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                listedTokenIds.pop();
                break;
            }
        }
    }

    function buyTicket(uint256 tokenId) external payable {
        Listing memory listing = listings[tokenId];
        require(listing.seller != address(0), "Not listed");
        require(msg.value == listing.price, "Incorrect ETH sent");

        TicketInfo storage info = ticketInfo[tokenId];
        uint256 resaleCap = info.originalPrice + ((info.originalPrice * resaleLimitPercent) / 100);

        require(msg.value <= resaleCap, "Price exceeds resale limit");
        require(info.resaleCount < resaleLimitCount, "Resale limit exceeded");

        payable(listing.seller).transfer(msg.value);
        _transfer(listing.seller, msg.sender, tokenId);

        info.resaleCount++;
        info.mintedAt = block.timestamp;
        info.lastSalePrice = msg.value;

        delete listings[tokenId];

        for (uint i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                listedTokenIds.pop();
                break;
            }
        }
    }

    // -------------------------------
    // View Functions
    // -------------------------------

    function getTicketInfo(uint256 tokenId) external view returns (TicketInfo memory) {
        return ticketInfo[tokenId];
    }

    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }

    function getAllListedTickets() external view returns (uint256[] memory) {
        return listedTokenIds;
    }

    function tokensOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 index = 0;

        for (uint256 tokenId = 1; tokenId < nextTokenId; tokenId++) {
            if (ownerOf(tokenId) == _owner) {
                tokenIds[index] = tokenId;
                index++;
            }
        }

        return tokenIds;
    }
}
