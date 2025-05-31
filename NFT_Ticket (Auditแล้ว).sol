// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; 

contract NFT_Ticket is ERC721, Ownable, ReentrancyGuard { 
    using Strings for uint256;

    uint256 public nextTokenId = 1;
    uint256 public constant RESALE_LIMIT_PERCENT = 20; 
    uint256 public constant RESALE_LIMIT_COUNT = 3; 
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
    mapping(uint256 => uint256) private previousLastSalePrice;
    mapping(uint256 => bool) public isListed;
    uint256[] public listedTokenIds;

    event TicketMinted(uint256 indexed tokenId, address indexed to, uint256 price);
    event TicketListed(uint256 indexed tokenId, uint256 price);
    event TicketCancelled(uint256 indexed tokenId); 
    event TicketBought(uint256 indexed tokenId, address indexed buyer, uint256 price);

    constructor(string memory _baseTokenURI) ERC721("NFT_Ticket", "TTT") Ownable(msg.sender) {
        baseTokenURI = _baseTokenURI;
    }

    // ---------------- Metadata ----------------

    function setBaseURI(string memory _uri) external onlyOwner {
        baseTokenURI = _uri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return string(abi.encodePacked(baseTokenURI, tokenId.toString(), ".json"));
    }

    // ---------------- Mint and Listing ----------------

    function mintAndListTickets(
        address to,
        uint256[] memory prices,
        uint256[] memory listingPrices
    ) external onlyOwner nonReentrant {
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

            uint256 maxResalePrice = prices[i] + (prices[i] * RESALE_LIMIT_PERCENT) / 100;
            require(listingPrices[i] <= maxResalePrice, "Listing price exceeds resale cap");

            listings[tokenId] = Listing({ seller: to, price: listingPrices[i] });

            if (!isListed[tokenId]) {
                listedTokenIds.push(tokenId);
                isListed[tokenId] = true;
            }

            emit TicketMinted(tokenId, to, prices[i]);
            emit TicketListed(tokenId, listingPrices[i]);

            nextTokenId++;
        }
    }

    function listTicket(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        TicketInfo storage info = ticketInfo[tokenId];
        uint256 basePrice = info.lastSalePrice > 0 ? info.lastSalePrice : info.originalPrice;
        uint256 maxResalePrice = basePrice + (basePrice * RESALE_LIMIT_PERCENT) / 100;

        require(price <= maxResalePrice, "Listing price exceeds resale cap");
        require(info.resaleCount < RESALE_LIMIT_COUNT, "Resale limit exceeded");

        previousLastSalePrice[tokenId] = info.lastSalePrice;

        listings[tokenId] = Listing({ seller: msg.sender, price: price });

        if (!isListed[tokenId]) {
            listedTokenIds.push(tokenId);
            isListed[tokenId] = true;
        }

        emit TicketListed(tokenId, price);
    }

    function cancelListing(uint256 tokenId) external {
        require(listings[tokenId].seller == msg.sender, "Not seller");

        ticketInfo[tokenId].lastSalePrice = previousLastSalePrice[tokenId];
        delete previousLastSalePrice[tokenId];
        delete listings[tokenId];

        if (isListed[tokenId]) {
            for (uint i = 0; i < listedTokenIds.length; i++) {
                if (listedTokenIds[i] == tokenId) {
                    listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                    listedTokenIds.pop();
                    break;
                }
            }
            isListed[tokenId] = false;
        }

        emit TicketCancelled(tokenId);
    }

    function buyTicket(uint256 tokenId) external payable nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.seller != address(0), "Not listed");
        require(msg.sender != listing.seller, "Seller cannot buy own ticket");
        require(msg.value == listing.price, "Incorrect ETH sent");
        

        TicketInfo storage info = ticketInfo[tokenId];
        uint256 basePrice = info.lastSalePrice > 0 ? info.lastSalePrice : info.originalPrice;
        uint256 maxResalePrice = basePrice + (basePrice * RESALE_LIMIT_PERCENT) / 100;

        require(msg.value <= maxResalePrice, "Price exceeds resale limit");
        require(info.resaleCount < RESALE_LIMIT_COUNT, "Resale limit exceeded");

        
         
    if (msg.sender != owner()) {
        require(balanceOf(msg.sender) < 4, "Cannot hold more than 4 tickets");
    }

        
        info.resaleCount++;
        info.mintedAt = block.timestamp;
        info.lastSalePrice = msg.value;

        delete listings[tokenId];

        if (isListed[tokenId]) {
            for (uint i = 0; i < listedTokenIds.length; i++) {
                if (listedTokenIds[i] == tokenId) {
                    listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                    listedTokenIds.pop();
                    break;
                }
            }
            isListed[tokenId] = false;
        }

        
        (bool sent, ) = listing.seller.call{value: msg.value}("");
        require(sent, "ETH transfer failed");

        _transfer(listing.seller, msg.sender, tokenId);

        emit TicketBought(tokenId, msg.sender, msg.value);
    }

    // ---------------- View Functions ----------------

    function getTicketInfo(uint256 tokenId) external view returns (TicketInfo memory) {
        return ticketInfo[tokenId];
    }

    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }

    function getAllListedTickets() external view returns (uint256[] memory) {
        return listedTokenIds;
    }

    function tokensOfOwner(address ownerAddr) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(ownerAddr);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 index = 0;

        for (uint256 tokenId = 1; tokenId < nextTokenId; tokenId++) {
            if (ownerOf(tokenId) == ownerAddr) {
                tokenIds[index++] = tokenId;
            }
        }

        return tokenIds;
    }
}
