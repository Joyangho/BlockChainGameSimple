// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Chainlink VRF v2.5 (Subscription)
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract GameTokenSABU_VRF is
    ERC20,
    ERC20Burnable,
    Pausable,
    ReentrancyGuard,
    VRFConsumerBaseV2Plus
{
    // ---- Token Sale (옵션) ----
    uint256 public immutable tokenPriceWei; // 1 SABU(whole) 당 wei
    uint256 public immutable maxSupply;     // base unit (10^decimals 포함)

    // ---- Game Params ----
    uint256 public immutable entryFeeBase;  // 1 SABU in base units
    uint256 public immutable rewardBase;    // 4 SABU in base units

    mapping(address => bool) public hasWon;

    // ---- VRF Config ----
    uint256 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    uint16 public immutable requestConfirmations;
    uint32 public immutable callbackGasLimit;

    // ---- Game Session (Commit/Reveal) ----
    enum GameState { NONE, WAITING_VRF, READY_TO_REVEAL }

    struct Session {
        GameState state;
        uint256 requestId;
        bytes32 pickCommit;   // keccak256(player, pickedIndex, salt)
        uint256 randomWord;   // VRF 결과 (리빌 전까지는 "정답 인덱스"를 저장하지 않음)
    }

    mapping(address => Session) private sessions;
    mapping(uint256 => address) private requestToPlayer;

    event GameStarted(address indexed player, uint256 indexed requestId, bytes32 pickCommit);
    event RandomnessReady(address indexed player, uint256 indexed requestId);
    event BoxRevealed(address indexed player, uint8 pickedIndex, uint8 winningIndex, bool won);

    event TokenPurchased(address indexed buyer, uint256 tokenAmountWhole, uint256 paidWei);

    constructor(
        // ---- VRF ----
        address vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        // ---- Token ----
        uint256 initialSupplyWhole,
        uint256 maxSupplyWhole,
        uint256 _tokenPriceWei
    )
        ERC20("SabuTestToken", "SABU")
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        require(maxSupplyWhole > 0, "maxSupply=0");
        require(_tokenPriceWei > 0, "tokenPrice=0");

        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;

        tokenPriceWei = _tokenPriceWei;
        maxSupply = maxSupplyWhole * 10 ** decimals();

        entryFeeBase = 1 * 10 ** decimals();
        rewardBase   = 4 * 10 ** decimals();

        _mintWithCap(msg.sender, initialSupplyWhole * 10 ** decimals());
    }

    // --------------------
    // Admin (Chainlink onlyOwner 사용: OZ Ownable 제거)
    // --------------------
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function mint(address to, uint256 amountBase) external onlyOwner {
        _mintWithCap(to, amountBase);
    }

    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "to=0");
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // --------------------
    // Token Sale (옵션)
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
    // Commit helper (프론트에서 그대로 계산해도 됨)
    // commit = keccak256(abi.encodePacked(player, pickedIndex, salt))
    // --------------------
    function makeCommit(address player, uint8 pickedIndex, bytes32 salt) public pure returns (bytes32) {
        require(pickedIndex < 4, "index 0~3");
        return keccak256(abi.encodePacked(player, pickedIndex, salt));
    }

    // --------------------
    // Game (VRF) - Commit 먼저 받고, VRF 후 Reveal만
    // --------------------
    function startGame(bytes32 pickCommit, bool enableNativePayment)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 reqId)
    {
        Session storage s = sessions[msg.sender];
        require(s.state == GameState.NONE, "game already active");
        require(pickCommit != bytes32(0), "commit=0");

        // 참가비 1 SABU 소각 (approve 불필요)
        _burn(msg.sender, entryFeeBase);

        reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: enableNativePayment })
                )
            })
        );

        requestToPlayer[reqId] = msg.sender;
        sessions[msg.sender] = Session({
            state: GameState.WAITING_VRF,
            requestId: reqId,
            pickCommit: pickCommit,
            randomWord: 0
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

        // VRF 결과로 정답 인덱스 결정
        winningIndex = uint8(s.randomWord % 4);

        won = (pickedIndex == winningIndex);
        hasWon[msg.sender] = won;

        if (won) {
            _mintWithCap(msg.sender, rewardBase);
        }

        delete sessions[msg.sender];

        emit BoxRevealed(msg.sender, pickedIndex, winningIndex, won);
    }

    // UI 조회용
    function getSession(address player)
        external
        view
        returns (GameState state, uint256 requestId, bool readyToReveal)
    {
        Session memory s = sessions[player];
        return (s.state, s.requestId, s.state == GameState.READY_TO_REVEAL);
    }

    // --------------------
    // Internals
    // --------------------
    function _mintWithCap(address to, uint256 amountBase) internal {
        require(totalSupply() + amountBase <= maxSupply, "cap exceeded");
        _mint(to, amountBase);
    }

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}
