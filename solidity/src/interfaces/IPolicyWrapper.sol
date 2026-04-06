// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPolicyWrapper {
    enum Status {
        None,
        Accepted,
        Rejected
    }

    struct TxData {
        address from;
        address to;
        uint256 amount;
        Status status;
        uint256 timeout;
    }

    event TokenWrap(
        address indexed from,
        address indexed to,
        uint256 amount,
        address indexed underlying
    );

    event TokenUnwrap(
        address indexed from,
        address indexed to,
        uint256 amount,
        address indexed underlying
    );

    event TxAccept(uint256 indexed id, uint256 timeout);
    event TxReject(uint256 indexed id);

    function rejectTx(uint256 id) external;

    function getTxData(uint256 id) external view returns (TxData memory);
}
