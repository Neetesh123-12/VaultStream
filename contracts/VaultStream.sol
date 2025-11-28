// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title VaultStream
 * @dev Simple ETH streaming vault: sender creates time-based payment streams to receivers
 * @notice Streams release funds linearly; receivers can withdraw vested amounts at any time
 */
contract VaultStream {
    address public owner;
    uint256 public nextStreamId;

    struct Stream {
        uint256 id;
        address sender;
        address recipient;
        uint256 deposit;      // total amount locked for this stream
        uint256 withdrawn;    // amount already withdrawn
        uint64  startTime;    // unix timestamp
        uint64  endTime;      // unix timestamp
        bool    isActive;
    }

    // streamId => Stream
    mapping(uint256 => Stream) public streams;

    event StreamCreated(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        uint256 deposit,
        uint64 startTime,
        uint64 endTime
    );

    event Withdrawn(
        uint256 indexed id,
        address indexed recipient,
        uint256 amount
    );

    event Canceled(
        uint256 indexed id,
        address indexed sender,
        uint256 refundToSender,
        uint256 payoutToRecipient
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier streamExists(uint256 id) {
        require(streams[id].sender != address(0), "Stream not found");
        _;
    }

    modifier onlySender(uint256 id) {
        require(streams[id].sender == msg.sender, "Not sender");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Create a new payment stream
     * @param recipient Receiver of the stream
     * @param startTime Start timestamp (must be >= now)
     * @param endTime End timestamp (> startTime)
     */
    function createStream(
        address recipient,
        uint64 startTime,
        uint64 endTime
    ) external payable returns (uint256 id) {
        require(recipient != address(0), "Zero recipient");
        require(msg.value > 0, "Deposit = 0");
        require(endTime > startTime, "Invalid time");

        id = nextStreamId++;
        streams[id] = Stream({
            id: id,
            sender: msg.sender,
            recipient: recipient,
            deposit: msg.value,
            withdrawn: 0,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit StreamCreated(id, msg.sender, recipient, msg.value, startTime, endTime);
    }

    /**
     * @dev Compute vested amount for a stream at current time
     */
    function vestedAmount(uint256 id)
        public
        view
        streamExists(id)
        returns (uint256)
    {
        Stream memory s = streams[id];

        if (block.timestamp <= s.startTime) {
            return 0;
        }
        if (block.timestamp >= s.endTime) {
            return s.deposit;
        }

        uint256 elapsed = block.timestamp - s.startTime;
        uint256 duration = s.endTime - s.startTime;
        return (s.deposit * elapsed) / duration;
    }

    /**
     * @dev Compute how much the recipient can withdraw now
     */
    function withdrawable(uint256 id)
        public
        view
        streamExists(id)
        returns (uint256)
    {
        Stream memory s = streams[id];
        if (!s.isActive) return 0;
        uint256 vested = vestedAmount(id);
        if (vested <= s.withdrawn) return 0;
        return vested - s.withdrawn;
    }

    /**
     * @dev Withdraw vested funds from a stream (recipient only)
     */
    function withdraw(uint256 id) external streamExists(id) {
        Stream storage s = streams[id];
        require(msg.sender == s.recipient, "Not recipient");
        require(s.isActive, "Inactive stream");

        uint256 amount = withdrawable(id);
        require(amount > 0, "Nothing withdrawable");

        s.withdrawn += amount;

        (bool ok, ) = payable(s.recipient).call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawn(id, s.recipient, amount);
    }

    /**
     * @dev Cancel a stream (sender only). Recipient gets vested part; sender gets the rest.
     */
    function cancel(uint256 id)
        external
        streamExists(id)
        onlySender(id)
    {
        Stream storage s = streams[id];
        require(s.isActive, "Already inactive");

        uint256 vested = vestedAmount(id);
        uint256 owedRecipient = vested > s.withdrawn ? (vested - s.withdrawn) : 0;
        uint256 remaining = s.deposit - s.withdrawn - owedRecipient;

        s.isActive = false;

        if (owedRecipient > 0) {
            (bool ok1, ) = payable(s.recipient).call{value: owedRecipient}("");
            require(ok1, "Recipient transfer failed");
        }

        if (remaining > 0) {
            (bool ok2, ) = payable(s.sender).call{value: remaining}("");
            require(ok2, "Sender refund failed");
        }

        emit Canceled(id, s.sender, remaining, owedRecipient);
    }

    /**
     * @dev Get contract ETH balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Transfer ownership of the vault stream manager
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        address prev = owner;
        owner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }
}
