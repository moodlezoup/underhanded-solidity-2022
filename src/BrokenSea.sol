// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC721.sol";
import "solmate/utils/SafeTransferLib.sol";


contract BrokenSea {
    using SafeTransferLib for ERC20;

    struct Ask {
        uint256 price;
        address seller;
    }

    // Asset pair key => NFT token ID => ask
    mapping(uint160 => mapping(uint256 => Ask)) asks;

    /// @dev Creates an ask for the given NFT. Can also be used to
    ///      update the price of an existing ask,
    /// @param erc721Token The ERC721 token contract.
    /// @param erc721TokenId The ID of the ERC721 asset to sell.
    /// @param erc20Token The ERC20 token contract.
    /// @param price The asking price, denominated in the given ERC20 token.
    ///        Providing a price of 0 cancels an existing ask if one exists.
    function createAsk(
        ERC721 erc721Token,
        uint256 erc721TokenId,
        ERC20 erc20Token,
        uint256 price
    )
        external
    {
        require(
            erc721Token.ownerOf(erc721TokenId) == msg.sender,
            "BrokenSea::createAsk/ONLY_TOKEN_OWNER"
        );
        require(price != 0, "BrokenSea::createAsk/ZERO_PRICE");

        uint160 key = _getKey(erc20Token, erc721Token);
        asks[key][erc721TokenId] = Ask({
            price: price,
            seller: msg.sender
        });
    }

    /// @dev Cancels an ask for the given NFT. Only callable
    ///      by the creator of the ask.
    /// @param erc721Token The ERC721 token contract.
    /// @param erc721TokenId The ID of the ERC721 asset to sell.
    /// @param erc20Token The ERC20 token contract.
    function cancelAsk(
        ERC721 erc721Token,
        uint256 erc721TokenId,
        ERC20 erc20Token
    )
        external
    {
        uint160 key = _getKey(erc20Token, erc721Token);
        require(
            asks[key][erc721TokenId].seller == msg.sender,
            "BrokenSea::cancelAsk/ONLY_SELLER"
        );
        delete asks[key][erc721TokenId];
    }

    /// @dev Fills
    /// @param erc721Token The ERC721 token contract.
    /// @param erc721TokenId The ID of the ERC721 asset to sell.
    /// @param erc20Token The ERC20 token contract.
    /// @param price The price the caller is willing to pay.
    ///        Reverts if the asking price exceeds this amount.
    function fillAsk(
        ERC721 erc721Token,
        uint erc721TokenId,
        ERC20 erc20Token,
        uint256 price
    )
        external
    {
        uint160 key = _getKey(erc20Token, erc721Token);
        Ask memory ask = asks[key][erc721TokenId];
        // If the ask price is 0, either the ask hasn't been
        // created yet or it has been cancelled.
        require(ask.price != 0, "BrokenSea::fillAsk/ASK_PRICE_ZERO");
        // Check that the ask price is at most the taker's price.
        // This prevents the seller from front-running the fill and
        // increasing the price.
        require(ask.price <= price, "BrokenSea::fillAsk/EXCEEDS_PRICE");

        // Mark ask as filled before performing transfers.
        delete asks[key][erc721TokenId];

        // solmate's SafeTransferLib uses a low-level call, so we
        // need to manually check that the contract exists.
        uint256 size;
        assembly { size := extcodesize(erc20Token) }
        require(size > 0, "BrokenSea::fillAsk/NO_CODE");
        erc20Token.safeTransferFrom(
            msg.sender,
            ask.seller,
            price
        );

        // Since this is _not_ a low-level call, the Solidity
        // compiler will insert an `extcodesize` check like the one
        // above; no need to do it ourselves here.
        // Reverts if the seller no longer owns the NFT.
        erc721Token.transferFrom(
            ask.seller,
            msg.sender,
            erc721TokenId
        );
    }

    // The `asks` storage mapping could be keyed by erc20Token and
    // erc721Token individually, i.e.
    // asks[erc20Token][erc721Token][erc721TokenId]
    // but that would require computing 3 keccak256 hashes per read/write.
    // As a minor gas optimization, the `asks` storage mapping is instead
    // keyed by the XOR of the two addresses, i.e.
    // asks[erc20Token ^ erc721Token][erc721TokenId]
    // It is statistically impossible to farm contract addresses that would
    // create a key collision.
    function _getKey(
        ERC20 erc20Token,
        ERC721 erc721Token
    )
        private
        pure
        returns (uint160 key)
    {
        return uint160(address(erc20Token)) ^ uint160(address(erc721Token));
    }
}

