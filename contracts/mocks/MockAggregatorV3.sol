// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface AggregatorV3InterfaceLike {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract MockAggregatorV3 is AggregatorV3InterfaceLike {
    uint8 public override decimals;
    int256 private _answer;
    uint256 private _updatedAt;

    // decimals_: 预言机的价格精度，表示 answer 按 10^decimals 缩放后的整数位数，常见喂价是 8 位小数。
    // answer_: 初始报价（最新值），按上面 decimals_ 放大后的整数
    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        setAnswer(answer_);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _answer, 0, _updatedAt, 0);
    }

    function setAnswer(int256 newAnswer) public {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
    }
}
