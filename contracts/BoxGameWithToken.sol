/*
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GameTokenSABU is ERC20, Ownable, Pausable {
    using SafeMath for uint256;
    uint256 public _tokenPrice = 0.0001 ether; // 토큰 판매
    uint256 public maxSupply = 100000000000 * 10 ** decimals(); // 전체 최대 발행량
    mapping(address => bool) public hasWon;

    // 생성자 함수, 토큰명, 토큰심볼, 초기발행량, 소수점 자리수를 설정합니다.
    constructor(uint256 initialSupply) 
    ERC20("SabuTestToken", "SABU") {
        _mint(msg.sender, initialSupply.mul(10 ** decimals())); // 초기 발행
    }

    // 전송 기능, ERC20 표준의 transfer 함수
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        super.transfer(to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        super.approve(spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }

   // 추가 발행 기능, 특정 주소에 토큰을 추가 발행하며 총 발행량이 증가
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Decimals를 고려하지 않는 Remix안에서만 함수 실행, 소각 기능, 본인 지갑 내의 토큰을 소각
    function burn(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount * 10 ** decimals());
    }

    // 토큰 전송 정지 기능
    function pause() public onlyOwner {
        pause();
    }

    // 토큰 전송 정지 해제 기능
    function unpause() public onlyOwner {
        unpause();
    }

    // 소유주 변경 기능
    function transferOwnership(address newOwner) public onlyOwner override {
        super.transferOwnership(newOwner);
    }

    // 전체 토큰 개수 확인
    function totalSupplyInToken() public view returns (uint256) {
        return totalSupply() / (10 ** decimals());
    }
    
    // 전체 맥스 토큰 개수 확인
    function totalMaxSupplyInToken() public view returns (uint256) {
        return maxSupply / (10 ** decimals());
    }

    // 특정 주소 토큰 개수 확인
    function balanceOfInToken(address account) public view returns (uint256) {
        return balanceOf(account) / (10 ** decimals());
    }

    // 현재 토큰 가격 조회 함수 추가
    function getTokenPrice() public view returns (uint256) {
        return _tokenPrice / (10 ** decimals());
    }

    // 웹에서 스왑하는 토큰 함수
    function purchaseTokens(uint256 tokenAmount) public payable whenNotPaused {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(maxSupply >= totalSupply() + tokenAmount, "Exceeds max supply");
        uint256 ethAmount = tokenAmount * _tokenPrice;
        require(msg.value >= ethAmount, "Insufficient funds");
        _mint(msg.sender, tokenAmount * (10 ** decimals()));
    }

    // 판매된 이더리움 인출
    function withdraw() public payable onlyOwner{
        (bool os, ) = payable(owner()).call {
            value: address(this).balance
        }("");
        require(os);
    }

    // 당첨 여부 확인 함수
    function hasWonBox(address player) public view returns (bool) {
        return hasWon[player];
    }

    // 박스 선택 함수, 당첨 시 4 SABU 지급
    function chooseBox(address player) public returns (bool) {
        require(maxSupply > totalSupply() + 4 * (10 ** decimals()), "Exceeds max supply");
        hasWon[player] = false;
        // 간단한 랜덤 로직 (실제로는 더 복잡한 로직 필요)
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 4;

        // 25% 확률로 당첨후 전송 4개 
        if (randomNumber == 0) {
            _mint(msg.sender, 4 * 10 ** decimals());
            hasWon[msg.sender] = true;
            return true;
        }
        return false;
    }
}