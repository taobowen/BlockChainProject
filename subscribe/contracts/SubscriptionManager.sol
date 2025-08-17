// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./AccessPass.sol";

/**
 * @title SubscriptionManager
 * @notice Manages paid subscription plans and mints/renews NFT access passes.
 *         - Provider creates/toggles plans and withdraws funds.
 *         - Subscriber approves stablecoin and subscribes to a plan.
 *         - Pass validity is time-based with a grace period.
 *         - Emits reminder events near expiry (for off-chain automation/notifications).
 */

contract SubscriptionManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Plan {
        uint256 price;
        uint32  duration;
        address paymentToken;
        bool    active;
    }

    mapping(uint256 => Plan) public plans;
    uint256 public nextPlanId;

    mapping(uint256 => uint256) public tokenPlan;
    mapping(uint256 => bool) public reminderSent;
    mapping(address => bool) public allowedTokens;

    AccessPass public immutable pass;
    uint32 public gracePeriod;
    uint32 public reminderWindow;

    // ====== Events ======

    event PlanCreated(uint256 indexed planId, uint256 price, uint32 duration, address indexed token);
    event PlanActiveSet(uint256 indexed planId, bool active);
    event AllowedTokenSet(address indexed token, bool allowed);

    event Subscribed(address indexed user, uint256 indexed tokenId, uint256 indexed planId, uint256 expiresAt);
    event Renewed(address indexed user, uint256 indexed tokenId, uint256 indexed planId, uint256 newExpiresAt);
    event Cancellation(address indexed user, uint256 indexed tokenId, uint256 when);
    event RenewalReminder(uint256 indexed tokenId, uint256 at);
    event Withdrawal(address indexed token, address indexed to, uint256 amount);

    // ====== Errors ======

    error InactivePlan();
    error TokenNotAllowed();
    error NotTokenOwner();
    error InvalidPlan();
    error InvalidArg();

    // ====== Constructor ======

    constructor(address accessPassAddr, uint32 _gracePeriod, uint32 _reminderWindow)
        Ownable(msg.sender)                // ✅ pass initial owner to base
    {
        if (accessPassAddr == address(0)) revert InvalidArg();
        pass = AccessPass(accessPassAddr);
        gracePeriod = _gracePeriod;
        reminderWindow = _reminderWindow;
    }

    // ====== Admin config ======

    function setGracePeriod(uint32 newGrace) external onlyOwner {
        gracePeriod = newGrace;
    }

    function setReminderWindow(uint32 newWindow) external onlyOwner {
        reminderWindow = newWindow;
    }

    function setAllowedToken(address token, bool allowed) external onlyOwner {
        allowedTokens[token] = allowed;
        emit AllowedTokenSet(token, allowed);
    }

    // ====== Plan management ======

    function createPlan(uint256 price, uint32 duration, address token) external onlyOwner returns (uint256 id) {
        if (price == 0 || duration == 0 || token == address(0)) revert InvalidArg();
        if (!allowedTokens[token]) revert TokenNotAllowed();

        id = ++nextPlanId;
        plans[id] = Plan({price: price, duration: duration, paymentToken: token, active: true});
        emit PlanCreated(id, price, duration, token);
    }

    function setPlanActive(uint256 planId, bool active) external onlyOwner {
        Plan storage p = plans[planId];
        if (p.paymentToken == address(0)) revert InvalidPlan();
        p.active = active;
        emit PlanActiveSet(planId, active);
    }

    // ====== Core flows ======

    /// @notice Subscribe to a plan: pulls payment, mints pass, sets expiry.
    function subscribe(uint256 planId) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        Plan memory p = plans[planId];
        if (p.paymentToken == address(0)) revert InvalidPlan();
        if (!p.active) revert InactivePlan();

        IERC20(p.paymentToken).safeTransferFrom(msg.sender, address(this), p.price);

        uint256 expiry = block.timestamp + p.duration;
        tokenId = pass.mintTo(msg.sender, expiry);
        tokenPlan[tokenId] = planId;
        reminderSent[tokenId] = false;

        emit Subscribed(msg.sender, tokenId, planId, expiry);
    }

    /// @notice Renew a pass under a (possibly different) plan.
    /// @dev Allows plan upgrades/downgrades: pass the target `planId`.
    function renew(uint256 tokenId, uint256 planId) external whenNotPaused nonReentrant {
        if (pass.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        Plan memory p = plans[planId];
        if (p.paymentToken == address(0)) revert InvalidPlan();
        if (!p.active) revert InactivePlan();

        IERC20(p.paymentToken).safeTransferFrom(msg.sender, address(this), p.price);

        // Extend from the later of "now" or current expiry
        uint256 currentExpiry = pass.expiresAt(tokenId);
        uint256 base = currentExpiry > block.timestamp ? currentExpiry : block.timestamp;
        uint256 newExpiry = base + p.duration;

        pass.setExpiry(tokenId, newExpiry);
        tokenPlan[tokenId] = planId;
        reminderSent[tokenId] = false; // allow new reminder for the new period

        emit Renewed(msg.sender, tokenId, planId, newExpiry);
    }

    /// @notice Cancel immediately by setting expiry to the current timestamp.
    function cancel(uint256 tokenId) external whenNotPaused nonReentrant {
        if (pass.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        pass.setExpiry(tokenId, block.timestamp);
        emit Cancellation(msg.sender, tokenId, block.timestamp);
    }

    // ====== Views & helpers ======

    /// @notice Returns true if token is within expiry + grace.
    function isActive(uint256 tokenId) public view returns (bool) {
        uint256 expiry = pass.expiresAt(tokenId);
        return block.timestamp < (expiry + gracePeriod);
    }

    /// @notice Returns true if `user` owns the token and it is active (grace included).
    function canAccess(address user, uint256 tokenId) external view returns (bool) {
        return pass.ownerOf(tokenId) == user && isActive(tokenId);
    }

    /// @notice Emits a RenewalReminder once per period when inside the reminder window.
    /// @dev This is a public function so any off-chain agent/cron can call it.
    function checkForReminder(uint256 tokenId) external whenNotPaused {
        if (reminderSent[tokenId]) return;
        uint256 expiry = pass.expiresAt(tokenId);
        if (reminderWindow == 0) return;
        if (block.timestamp + reminderWindow >= expiry && block.timestamp < expiry) {
            reminderSent[tokenId] = true;
            emit RenewalReminder(tokenId, block.timestamp);
        }
    }

    // ====== Treasury ======

    /// @notice Withdraw accumulated funds.
    function withdraw(address erc20, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0) || erc20 == address(0) || amount == 0) revert InvalidArg();
        IERC20(erc20).safeTransfer(to, amount);
        emit Withdrawal(erc20, to, amount);
    }

    // ====== Admin safety switches ======

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
