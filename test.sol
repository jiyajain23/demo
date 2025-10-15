// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Multi-Party Payment Splitter (no imports, no constructor)
/// @notice Accepts ETH and allows splitting payouts among configured payees by shares.
/// @dev Owner must call init() once after deployment to claim ownership.
contract PaymentSplitter {
    /* ========== STATE ========== */
    address public owner;
    address[] public payees;

    mapping(address => uint256) public shares;     // shares per payee
    mapping(address => uint256) public released;   // amount already released per payee

    uint256 public totalShares;
    uint256 public totalReleased;

    /* ========== EVENTS ========== */
    event PayeeAdded(address indexed account, uint256 shares);
    event PayeeRemoved(address indexed account);
    event PaymentReceived(address indexed from, uint256 amount);
    event PaymentReleased(address indexed to, uint256 amount);
    event OwnerInit(address indexed owner);

    /* ========== MODIFIERS ========== */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyUninitialized() {
        require(owner == address(0), "Already initialized");
        _;
    }

    /* ========== INITIALIZATION (no constructor) ========== */
    /// @notice Call once after deployment to set the owner (deployer should call it)
    function init() external onlyUninitialized {
        owner = msg.sender;
        emit OwnerInit(owner);
    }

    /* ========== PAYEE MANAGEMENT ========== */

    /// @notice Add a payee with `numShares`. Only owner.
    function addPayee(address account, uint256 numShares) external onlyOwner {
        require(account != address(0), "Invalid address");
        require(numShares > 0, "Shares = 0");
        require(shares[account] == 0, "Payee exists");

        payees.push(account);
        shares[account] = numShares;
        totalShares += numShares;

        emit PayeeAdded(account, numShares);
    }

    /// @notice Remove a payee. Only owner. Removes shares and deletes from list.
    /// @dev This does not attempt to return previous funds — released[] remains as-is.
    function removePayee(address account) external onlyOwner {
        require(shares[account] > 0, "No such payee");

        // subtract shares
        totalShares -= shares[account];
        shares[account] = 0;

        // remove from array (swap & pop for gas efficiency)
        for (uint256 i = 0; i < payees.length; ++i) {
            if (payees[i] == account) {
                payees[i] = payees[payees.length - 1];
                payees.pop();
                break;
            }
        }

        emit PayeeRemoved(account);
    }

    /* ========== RECEIVE / FALLBACK ========== */

    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    /* ========== PAYOUT LOGIC ========== */

    /// @notice Returns amount currently releasable for `account`
    function releasable(address account) public view returns (uint256) {
        require(shares[account] > 0, "Account has no shares");
        uint256 totalReceived = address(this).balance + totalReleased;
        uint256 payment = (totalReceived * shares[account]) / totalShares - released[account];
        return payment;
    }

    /// @notice Release owed funds to `account`. Can be called by anyone.
    function release(address payable account) public {
        require(shares[account] > 0, "No shares for account");

        uint256 payment = releasable(account);
        require(payment > 0, "No payment due");

        // update accounting before transfer (checks-effects-interactions)
        released[account] += payment;
        totalReleased += payment;

        (bool success, ) = account.call{value: payment}("");
        require(success, "Transfer failed");

        emit PaymentReleased(account, payment);
    }

    /// @notice Owner convenience function to release funds to all payees.
    function releaseAll() external onlyOwner {
        // iterate snapshot of payees to avoid reentrancy issues with dynamic changes
        address[] memory snapshot = payees;
        for (uint256 i = 0; i < snapshot.length; ++i) {
            address payable p = payable(snapshot[i]);
            if (releasable(p) > 0) {
                release(p);
            }
        }
    }

    /* ========== VIEW HELPERS ========== */

    /// @notice Number of payees
    function payeeCount() external view returns (uint256) {
        return payees.length;
    }

    /// @notice Get payee at index
    function payeeAt(uint256 i) external view returns (address) {
        return payees[i];
    }
}
