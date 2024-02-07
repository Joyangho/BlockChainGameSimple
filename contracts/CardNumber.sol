// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 외부 난수 불러오기 위해선 체인링크 가스비 필요
// import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract CardGame {
    // 이벤트 선언
    event NumberGenerated(uint blueNumber, uint redNumber, address winner);
    event TokensDeposited(address indexed player, uint amount);
    event TokensWithdrawn(address indexed player, uint amount);

    // 이전 결과를 저장하는 변수
    uint private previousResultBlue;
    uint private previousResultRed;

    // mumbai 네트워크의 토큰 컨트랙트 주소
    address public constant TOKEN_ADDRESS = 0x4f651f2468aB866E8a6f331544975F65C60E8b1B;

    // 당첨 여부 확인을 위한 매핑
    mapping(address => bool) public hasWon;
    mapping(address => uint) public tokenBalance;

    // 당첨 여부 확인 함수
    function hasWonAddress(address winnerAddress) public view returns (bool) {
        return hasWon[winnerAddress];
    }

    // 플레이어가 블루 또는 레드를 선택하고 카드를 뽑는 함수
    function playCard(bool choice) public {
        uint256 currentBalance = IERC20(TOKEN_ADDRESS).balanceOf(address(this));
        uint256 PlayerBalance = tokenBalance[msg.sender];

        // 보상하기 위해 필요한 토큰의 최소량 계산
        uint256 requiredTokens = 2 * (10 ** 18);

        // 현재 잔액이 보상에 필요한 토큰보다 같으면 함수를 종료하고 오류 발생
        require(currentBalance > requiredTokens, "Insufficient tokens");
        require(currentBalance > PlayerBalance, "Insufficient tokens");

        hasWon[msg.sender] = false;

        // 랜덤 숫자 생성
        uint randomNumberBlue = uint(keccak256(abi.encodePacked(block.timestamp - 1, block.number, msg.sender))) % 10;
        uint randomNumberRed = uint(keccak256(abi.encodePacked(block.timestamp - 3, block.number, block.coinbase))) % 10;

        // 블루와 레드의 숫자 생성
        uint blueNumber = randomNumberBlue;
        uint redNumber = randomNumberRed;

        address winnerAddress;

        if (blueNumber > redNumber) {
            winnerAddress = choice ? msg.sender : address(this); // 블루가 승리하면 블루 플레이어가, 레드가 승리하면 스마트 계약이 승자가 됨
        } else if (redNumber > blueNumber) {
            winnerAddress = choice ? address(this) : msg.sender; // 레드가 승리하면 레드 플레이어가, 블루가 승리하면 스마트 계약이 승자가 됨
        } else {
            winnerAddress = address(0); // 동점일 경우는 무승부
        }
        emit NumberGenerated(blueNumber, redNumber, winnerAddress);

        // 이전 결과 저장
        previousResultBlue = randomNumberBlue;
        previousResultRed = randomNumberRed;

        // 승자에게 토큰을 보상
        if (winnerAddress == msg.sender) {
            hasWon[msg.sender] = true;
            tokenBalance[msg.sender] += 2 * (10 ** 18);
            emit TokensDeposited(msg.sender, 2 * (10 ** 18));
        }
    }

    // 이전 결과를 가져오는 함수
    function getPreviousResults() public view returns (uint, uint) {
        return (previousResultBlue, previousResultRed);
    }

    // 승자가 토큰에서 지갑을 빼내는 함수
    function withdrawTokens() public {
        uint256 amount = tokenBalance[msg.sender];
        require(amount > 0, "No tokens to withdraw");

        emit TokensWithdrawn(msg.sender, amount);
    
        // CardGame 컨트랙트가 충분한 토큰 인출 권한을 가지도록 approve 함수 호출
        IERC20(TOKEN_ADDRESS).approve(address(this), amount);

        // 토큰을 지갑으로 전송
        IERC20(TOKEN_ADDRESS).transferFrom(address(this), msg.sender, amount);
        tokenBalance[msg.sender] = 0; // 적립된 토큰을 초기화
    }

    // 토큰 밸런스 호출
    function getTokenBalance() public view returns (uint) {
        return tokenBalance[msg.sender] / (10 ** 18);
    }

    // 컨트랙트의 토큰 잔액을 조회하는 함수
    function viewContractTokenBalance() public view returns (uint) {
        return IERC20(TOKEN_ADDRESS).balanceOf(address(this)) / (10 ** 18);
    }

}
