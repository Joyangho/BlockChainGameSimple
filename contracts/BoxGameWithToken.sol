// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Chainlink VRF v2.5 (Subscription)
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract GameTokenSABU_VRF is
    ERC20,
    Pausable,
    ReentrancyGuard,
    VRFConsumerBaseV2Plus
{
    // ---- Token Sale ----
    uint256 public immutable tokenPriceWei; // 1 SABU(whole) 당 wei
    uint256 public immutable maxSupply;     // base unit (10^decimals 포함)

    // ---- Game Params ----
    uint256 public immutable entryFeeBase;  // 1 SABU in base units
    uint256 public immutable rewardBase;    // 4 SABU in base units

    // ---- Timeouts ----
    uint256 public immutable vrfTimeoutSeconds;
    uint256 public immutable revealTimeoutSeconds;

    mapping(address => bool) public hasWon;

    // ---- VRF Config ----
    uint256 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    uint16 public immutable requestConfirmations;
    uint32 public immutable callbackGasLimit;

    bool public payWithNative; // 운영자가 고정 (유저 입력 제거)

    // ---- Game Session (Escrow + Commit/Reveal) ----
    enum GameState { NONE, WAITING_VRF, READY_TO_REVEAL }

    struct Session {
        GameState state;
        uint256 requestId;
        bytes32 pickCommit;   // keccak256(player, pickedIndex, salt)
        uint256 randomWord;   // VRF 결과
        uint64  startedAt;
        uint64  readyAt;
    }

    mapping(address => Session) private sessions;
    mapping(uint256 => address) private requestToPlayer;

    // ---- Events ----
    event GameStarted(address indexed player, uint256 indexed requestId, bytes32 pickCommit);
    event RandomnessReady(address indexed player, uint256 indexed requestId);
    event BoxRevealed(address indexed player, uint8 pickedIndex, uint8 winningIndex, bool won);

    event VrfTimeoutCancelled(address indexed player, uint256 indexed requestId, uint256 refunded);
    event RevealTimeoutForfeited(address indexed player, uint256 indexed requestId, uint256 burned);

    event TokenPurchased(address indexed buyer, uint256 tokenAmountWhole, uint256 paidWei);
    event PayWithNativeSet(bool enabled);

    constructor(
        // ---- VRF ----
        address vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _payWithNative,
        // ---- Token ----
        uint256 initialSupplyWhole,
        uint256 maxSupplyWhole,
        uint256 _tokenPriceWei,
        // ---- Timeouts ----
        uint256 _vrfTimeoutSeconds,
        uint256 _revealTimeoutSeconds
    )
        ERC20("SabuTestToken", "SABU")
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        require(maxSupplyWhole > 0, "maxSupply=0");
        require(_tokenPriceWei > 0, "tokenPrice=0");
        require(_vrfTimeoutSeconds >= 60, "vrf timeout small");
        require(_revealTimeoutSeconds >= 60, "reveal timeout small");

        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;

        payWithNative = _payWithNative;

        tokenPriceWei = _tokenPriceWei;
        maxSupply = maxSupplyWhole * 10 ** decimals();

        entryFeeBase = 1 * 10 ** decimals();
        rewardBase   = 4 * 10 ** decimals();

        vrfTimeoutSeconds = _vrfTimeoutSeconds;
        revealTimeoutSeconds = _revealTimeoutSeconds;

        _mintWithCap(msg.sender, initialSupplyWhole * 10 ** decimals());
    }

    // --------------------
    // Admin (Chainlink onlyOwner)
    // --------------------
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function setPayWithNative(bool enabled) external onlyOwner {
        payWithNative = enabled;
        emit PayWithNativeSet(enabled);
    }

    function mint(address to, uint256 amountBase) external onlyOwner {
        _mintWithCap(to, amountBase);
    }

    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "to=0");
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // --------------------
    // Token Sale
    // --------------------
    function purchaseTokens(uint256 tokenAmountWhole) external payable whenNotPaused nonReentrant {
        require(tokenAmountWhole > 0, "amount=0");

        uint256 cost = tokenAmountWhole * tokenPriceWei;
        require(msg.value == cost, "wrong ETH");

        uint256 amountBase = tokenAmountWhole * 10 ** decimals();
        _mintWithCap(msg.sender, amountBase);

        emit TokenPurchased(msg.sender, tokenAmountWhole, msg.value);
    }

    // --------------------
    // Commit helper
    // commit = keccak256(abi.encodePacked(player, pickedIndex, salt))
    // --------------------
    function makeCommit(address player, uint8 pickedIndex, bytes32 salt) public pure returns (bytes32) {
        require(pickedIndex < 4, "index 0~3");
        return keccak256(abi.encodePacked(player, pickedIndex, salt));
    }

    // --------------------
    // Game (Escrow + Commit/Reveal + VRF)
    // --------------------
    function startGame(bytes32 pickCommit)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 reqId)
    {
        Session storage s = sessions[msg.sender];
        require(s.state == GameState.NONE, "game already active");
        require(pickCommit != bytes32(0), "commit=0");

        _transfer(msg.sender, address(this), entryFeeBase);

        reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: payWithNative })
                )
            })
        );

        requestToPlayer[reqId] = msg.sender;
        sessions[msg.sender] = Session({
            state: GameState.WAITING_VRF,
            requestId: reqId,
            pickCommit: pickCommit,
            randomWord: 0,
            startedAt: uint64(block.timestamp),
            readyAt: 0
        });

        emit GameStarted(msg.sender, reqId, pickCommit);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address player = requestToPlayer[requestId];
        if (player == address(0)) return;

        Session storage s = sessions[player];
        if (s.state != GameState.WAITING_VRF || s.requestId != requestId) return;

        s.randomWord = randomWords[0];
        s.state = GameState.READY_TO_REVEAL;
        s.readyAt = uint64(block.timestamp);

        delete requestToPlayer[requestId];

        emit RandomnessReady(player, requestId);
    }

    function revealPick(uint8 pickedIndex, bytes32 salt)
        external
        whenNotPaused
        nonReentrant
        returns (bool won, uint8 winningIndex)
    {
        require(pickedIndex < 4, "index 0~3");

        Session memory s = sessions[msg.sender];
        require(s.state == GameState.READY_TO_REVEAL, "not ready");

        bytes32 expected = keccak256(abi.encodePacked(msg.sender, pickedIndex, salt));
        require(expected == s.pickCommit, "bad reveal");

        winningIndex = uint8(s.randomWord % 4);
        won = (pickedIndex == winningIndex);

        _burn(address(this), entryFeeBase);

        hasWon[msg.sender] = won;
        if (won) {
            _mintWithCap(msg.sender, rewardBase);
        }

        delete sessions[msg.sender];

        emit BoxRevealed(msg.sender, pickedIndex, winningIndex, won);
    }

    function cancelAfterVrfTimeout() external nonReentrant {
        Session memory s = sessions[msg.sender];
        require(s.state == GameState.WAITING_VRF, "not waiting");
        require(block.timestamp > uint256(s.startedAt) + vrfTimeoutSeconds, "not timed out");

        delete requestToPlayer[s.requestId];
        delete sessions[msg.sender];

        _transfer(address(this), msg.sender, entryFeeBase);

        emit VrfTimeoutCancelled(msg.sender, s.requestId, entryFeeBase);
    }

    function forfeitAfterRevealTimeout(address player) external nonReentrant {
        Session memory s = sessions[player];
        require(s.state == GameState.READY_TO_REVEAL, "not reveal state");
        require(block.timestamp > uint256(s.readyAt) + revealTimeoutSeconds, "not timed out");

        delete sessions[player];

        _burn(address(this), entryFeeBase);

        emit RevealTimeoutForfeited(player, s.requestId, entryFeeBase);
    }

    function getSession(address player)
        external
        view
        returns (
            GameState state,
            uint256 requestId,
            bool readyToReveal,
            uint256 startedAt,
            uint256 readyAt
        )
    {
        Session memory s = sessions[player];
        return (
            s.state,
            s.requestId,
            s.state == GameState.READY_TO_REVEAL,
            uint256(s.startedAt),
            uint256(s.readyAt)
        );
    }

    // --------------------
    // Internals
    // --------------------
    function _mintWithCap(address to, uint256 amountBase) internal {
        require(totalSupply() + amountBase <= maxSupply, "cap exceeded");
        _mint(to, amountBase);
    }

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
