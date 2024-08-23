// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IOracle {
    struct priceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    function getSvalue(
        uint256 pairIndex
    ) external view returns (priceFeed memory);
}

interface IPythOracle {
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    // PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }

    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PriceFeed[] memory priceFeeds);

    function queryPriceFeed(
        bytes32 id
    ) external view returns (PriceFeed memory priceFeed);
}
