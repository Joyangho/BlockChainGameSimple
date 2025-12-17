// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Chainlink VRF v2.5 (Subscription)
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract GameTokenSABU_VRF is
    ERC20,
    ERC20Burnable,
    Ownable,
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

    // ---- Game Session ----
    enum GameState { NONE, WAITING_VRF, READY_TO_PICK }
    struct Session {
        GameState state;
        uint256 requestId;
        uint8 winningIndex; // 0~3
        bool picked;
    }
    mapping(address => Session) private sessions;
    mapping(uint256 => address) private requestToPlayer;

    event GameStarted(address indexed player, uint256 indexed requestId);
    event RandomnessReady(address indexed player, uint256 indexed requestId, uint8 winningIndex);
    event BoxPicked(address indexed player, uint8 pickedIndex, bool won);

    event TokenPurchased(address indexed buyer, uint256 tokenAmountWhole, uint256 paidWei);

    constructor(
        // ---- VRF ----
        address vrfCoordinator,          // 네트워크별 Coordinator 주소
        uint256 _subscriptionId,         // Subscription ID
        bytes32 _keyHash,                // Gas lane keyHash
        uint16 _requestConfirmations,    // 보통 3~
        uint32 _callbackGasLimit,        // fulfill 가스
        // ---- Token ----
        uint256 initialSupplyWhole,
        uint256 maxSupplyWhole,
        uint256 _tokenPriceWei
    )
        ERC20("SabuTestToken", "SABU")
        Ownable(msg.sender)
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
    // Admin
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
    // Game (VRF)
    // --------------------

    /// @notice Start 버튼: 1 SABU 참가비(소각) + VRF 요청
    /// @dev 프론트: 먼저 approve(entryFeeBase) 필요
    /// @param enableNativePayment true=네이티브(예: ETH/MATIC)로 VRF 결제, false=LINK로 결제
    function startGame(bool enableNativePayment) external whenNotPaused nonReentrant returns (uint256 reqId) {
        Session storage s = sessions[msg.sender];
        require(s.state == GameState.NONE, "game already active");

        // 참가비 1 SABU 소각(=“사라짐” 요구사항 충족)
        burnFrom(msg.sender, entryFeeBase);

        // VRF v2.5 request format (extraArgs 포함)
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
            winningIndex: 0,
            picked: false
        });

        emit GameStarted(msg.sender, reqId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address player = requestToPlayer[requestId];
        require(player != address(0), "unknown request");

        Session storage s = sessions[player];

        require(s.state == GameState.WAITING_VRF && s.requestId == requestId, "stale request");

        uint8 win = uint8(randomWords[0] % 4);
        s.winningIndex = win;
        s.state = GameState.READY_TO_PICK;

        delete requestToPlayer[requestId];

        emit RandomnessReady(player, requestId, win);
    }

    // 4개 버튼 중 1개 클릭(0~3) - 1회만 가능, 맞으면 즉시 4 SABU 민팅
    function pickBox(uint8 pickedIndex) external whenNotPaused nonReentrant returns (bool won) {
        require(pickedIndex < 4, "index 0~3");

        Session storage s = sessions[msg.sender];
        require(s.state == GameState.READY_TO_PICK, "not ready");
        require(!s.picked, "already picked");

        s.picked = true;
        s.state = GameState.NONE;

        won = (pickedIndex == s.winningIndex);
        hasWon[msg.sender] = won;

        if (won) {
            _mintWithCap(msg.sender, rewardBase);
        }

        emit BoxPicked(msg.sender, pickedIndex, won);

        delete sessions[msg.sender];
        return won;
    }

    // UI 조회용
    function getSession(address player)
        external
        view
        returns (GameState state, uint256 requestId, bool picked, bool readyToPick)
    {
        Session memory s = sessions[player];
        return (s.state, s.requestId, s.picked, s.state == GameState.READY_TO_PICK);
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
