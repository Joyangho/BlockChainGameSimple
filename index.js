/*
Ethereum = 1
Goerli 테스트 네트워크 = 5
Polygon Mainnet = 137;
Polygon Mumbai testnet = 80001;
*/
const Network = 80001;

(async () => {
    setMintCount();
})();

var WalletAddress = "";
var WalletBalance = "";

function networkCheck() {
    if (window.web3._provider.networkVersion != Network) {
        alert("폴리곤 mumbai로 네트워크를 변경해주세요.", "", "warning");
        return true; // 네트워크가 일치하지 않을 때
    }
    return false; // 네트워크가 일치
}

async function connectWallet() {
    if (window.ethereum) {
        if (window.ethereum.isTrust) {
            alert("트러스트 월렛말고 메타마스크를 사용해주세요.", "", "warning");
            return;
        }
        await window.ethereum.send('eth_requestAccounts');
        window.web3 = new Web3(window.ethereum);
        if (networkCheck()) {
            // 네트워크가 일치하지 않으면 종료
            return;
        }

        var accounts = await web3.eth.getAccounts();
        WalletAddress = accounts[0];
        WalletBalance = await web3.eth.getBalance(WalletAddress);

        contract = new web3.eth.Contract(ABI, ADDRESS);
        tokenBalance = await contract.methods.balanceOf(WalletAddress).call();

        tokenBalanceInEther = web3.utils.fromWei(tokenBalance);

        console.log("SABU Token Balance:", tokenBalanceInEther);

        if (web3.utils.fromWei(WalletBalance) < 0.0001) {
            alert("You need more MATIC");
        } else {
            document.getElementById("txtWalletBalance").innerHTML = web3.utils.fromWei(WalletBalance).substr(0, 6);
            var txtAccount = accounts[0].substr(0, 5) + ' . . . . . . ' + accounts[0].substr(37, 42);
            document.getElementById("walletInfo").style.display = "block";
            document.getElementById("btnConnectWallet").style.display = "none";
            document.getElementById("txtWalletAddress").innerHTML = txtAccount;
            document.getElementById("balanceOfToken").innerHTML = tokenBalanceInEther;
        }
    }
}
document.getElementById('walletrefresh').addEventListener('click', async () => {
    await connectWallet(); // 버튼 클릭 시 토큰 잔액 새로고침
});

// 입력값을 받아와서 0.0001을 곱한 후 결과를 업데이트하는 함수
function calculateResult() {
    // 입력값 가져오기
    var inputValue = document.getElementById("txtMintAmount").value;

    // 입력값이 비어있지 않은 경우에만 계산 수행
    if (inputValue !== "") {
        // 0.0001을 곱한 결과 계산
        var result = inputValue * 0.0001;
        var formattedResult = result.toFixed(4);

        // 결과를 화면에 업데이트
        document.getElementById("result").innerHTML = "필요한 MATIC: " + formattedResult + " + gas fee";
    } else {
        // 입력값이 비어있을 경우 결과를 0으로 설정
        document.getElementById("result").innerHTML = "필요한 MATIC:";
    }
}

async function setMintCount() {
    await window.ethereum.send('eth_requestAccounts');
    window.web3 = new Web3(window.ethereum);
    contract = new web3.eth.Contract(ABI, ADDRESS);

    if (contract) {
        var totalSupply = await contract.methods.totalSupplyInToken().call();
        document.getElementById("txtTotalSupply").innerHTML = totalSupply;
        var totalSupply = await contract.methods.totalMaxSupplyInToken().call();
        document.getElementById("txtMaxSupply").innerHTML = totalSupply;
    }
}

/*
Token을 메타마스크에 추가하는 함수
*/
async function TokenAdd() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 함수 종료
        return;
    }
    // Metamask에 추가할 토큰 정보
    const tokenInfo = {
        type: "ERC20", // 토큰 종류 (ERC20, BEP20 등)
        options: {
            address: ADDRESS, // 토큰의 스마트 컨트랙트 주소
            symbol: "SABU", // 토큰 심볼 (예: ETH, DAI)
            decimals: 18, // 토큰의 소수점 자리수
        },
    };

    try {
        // Metamask에 토큰 추가 요청
        await ethereum.request({
            method: 'wallet_watchAsset',
            params: tokenInfo,
        });

        alert("토큰이 메타마스크에 추가되었습니다.");
    } catch (error) {
        console.error("토큰 추가 오류:", error);
        alert("토큰 추가에 실패했습니다. 메타마스크 설정을 확인해주세요.");
    }
}

// 토큰 스왑
async function purchaseTokens() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    await window.ethereum.send('eth_requestAccounts');
    window.web3 = new Web3(window.ethereum);
    contract = new web3.eth.Contract(ABI, ADDRESS);

    if (contract) {
        var tokenAmount = document.getElementById("txtMintAmount").value;

        var transaction = await contract.methods.purchaseTokens(tokenAmount).send(
            {
                from: WalletAddress,
                value: web3.utils.toWei((0.0001 * tokenAmount).toFixed(4), 'ether') // 가격을 wei로 변환
            }
        ).on('error', function (error) {
            alert("먼저 지갑에 연결해주세요");
            console.log("Mint - 에러 : " + error);
        }).then(function (receipt) {
            alert("Mint Success!");
            console.log("Mint - 성공 : " + receipt);
        });
        console.log("Mint - 전송 : " + transaction);
    }
}

async function startSABUGame() {
    // SABU 게임 시작 로직을 추가
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    console.log("SABU Game started!");

    // Metamask에 추가할 토큰 정보
    const tokenInfo = {
        type: "ERC20", // 토큰 종류
        options: {
            address: ADDRESS, // 토큰의 스마트 컨트랙트 주소
            symbol: "SABU", // 토큰 심볼
            decimals: 18, // 토큰의 소수점 자리수
        },
    };

    try {
        // 사용자에게 팝업을 열라는 안내 메시지 표시
        alert("MetaMask를 확인해주세요. 게임을 시작하기 위해서 1 SABU를 전송합니다.");

        // 토큰 전송
        const transactionHash = await sendTokenToAddress("0xf4F2AF207618Bd639aA70eD9498A98CB8391BC26", '1', tokenInfo.options.address);
        // 토큰 전송 성공 시 동적 버튼 생성
        if (transactionHash) {
            console.log("게임을 시작합니다!");
            createButtons();
        } else {
            console.log("Token sending failed.");
        }
    } catch (error) {
        console.error("Error:", error);
    }
}

async function sendTokenToAddress(toAddress, amount, ADDRESS) {
    try {
        if (networkCheck()) {
            // 네트워크가 일치하지 않으면 종료
            return;
        }
        // MetaMask에 계정 요청
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const WalletAddress = accounts[0];

        // 스마트 컨트랙트 연결
        const contract = new window.web3.eth.Contract(ABI, ADDRESS);

        // 토큰 전송
        const transaction = await contract.methods.transfer(toAddress, window.web3.utils.toWei(amount, 'ether')).send({
            from: WalletAddress,
        });

        console.log("Token sent successfully!");
        return transaction.transactionHash;
    } catch (error) {
        console.error("Token sending failed:", error);
        return null;
    }
}

function createButtons() {
    // 버튼을 동적으로 생성
    const buttonContainer = document.createElement('div');
    buttonContainer.setAttribute('id', 'buttonContainer');

    for (let i = 1; i <= 4; i++) {
        const button = document.createElement('button');
        button.textContent = `SABU Token Random Box  ${i}`;
        button.setAttribute('onclick', `handleButtonClick(${i})`);
        buttonContainer.appendChild(button);
    }

    // 기존의 시작 버튼 대신 생성한 버튼을 추가
    const startButton = document.getElementById('startButton');
    startButton.replaceWith(buttonContainer);
}

async function handleButtonClick() {
    try {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const WalletAddress = accounts[0];
        // 4개의 버튼 중 이길 확률은 각각 25%이며, 이 확률은 블록체인에 기록되어있습니다.
        const isWinner = await contract.methods.chooseBox(WalletAddress).send({
            from: WalletAddress,
            gas: 4000000,  // 적절한 가스량 설정
        });

        if (isWinner) {
            // 4. 당첨된 1개의 버튼을 클릭 시 4 SABU가 당첨(기대값 일치)됩니다.
            const hasWon = await contract.methods.hasWonBox(WalletAddress).call();

            if (hasWon) {
                // 당첨된 경우에 처리할 내용 추가
                location.reload()
                alert("축하합니다! 당첨되셨습니다. 4 SABU가 전송 되었습니다!");
            } else {
                // 당첨되지 않은 경우에 처리할 내용 추가
                location.reload()
                alert("안타깝지만 당첨되지 않았습니다.");
            }
        }
    } catch (error) {
        console.error("Error handling button click:", error);
    }
}

// CardGame

// 컨트랙트 주소 및 ABI 정의
const CONTRACT_ADDRESS = ADDRESS_CARD;
const CONTRACT_ABI = ABI_CARD;

// Web3 인스턴스 생성
const web3 = new Web3(Web3.givenProvider);

// 계정 가져오기
async function getAccount() {
    const accounts = await web3.eth.requestAccounts();
    return accounts[0];
}

// 이벤트 처리
document.getElementById('playBlue').addEventListener('click', async () => {
    await playCard(true); // 블루 선택 시 playCard 함수 호출
});

document.getElementById('playRed').addEventListener('click', async () => {
    await playCard(false); // 레드 선택 시 playCard 함수 호출
});

// playCard 함수 호출
async function playCard(choice) {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    const account = await getAccount(); // 현재 사용자의 계정을 가져옴
    const contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS); // 스마트 계약과의 연결 생성

    try {
        // 스마트 계약에 playCard 함수 호출
        await contract.methods.playCard(choice).send({ from: account });
        console.log('Transaction successful'); // 트랜잭션이 성공한 경우 콘솔에 메시지 출력

        // 결과 표시
        const results = await getResults(); // 결과 가져오기
        document.getElementById('results').innerHTML = `Blue Number: ${results[0]} - Red Number: ${results[1]}`;

        // 승리 여부 확인
        const hasWon = await contract.methods.hasWonAddress(account).call();
        if (hasWon) {
            console.log('축하합니다! 당첨되었습니다.'); // 보상이 성공적으로 청구된 경우 콘솔에 메시지 출력
        } else {
            console.log('당첨되지 않았습니다.');
        }
    } catch (error) {
        console.error('Transaction failed:', error); // 트랜잭션이 실패한 경우 콘솔에 에러 메시지 출력
    }
}


// 결과 가져오기
async function getResults() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    const contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS); // 스마트 계약과의 연결 생성
    const results = await contract.methods.getPreviousResults().call(); // 이전 결과를 가져옴
    return results; // 결과 반환
}

async function startNUMBERGame() {
    // SABU 게임 시작 로직을 추가
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    console.log("NUMBER Game started!");

    // Metamask에 추가할 토큰 정보
    const tokenInfo = {
        type: "ERC20", // 토큰 종류
        options: {
            address: ADDRESS, // 토큰의 스마트 컨트랙트 주소
            symbol: "SABU", // 토큰 심볼
            decimals: 18, // 토큰의 소수점 자리수
        },
    };

    try {
        // 사용자에게 팝업을 열라는 안내 메시지 표시
        alert("MetaMask를 확인해주세요. 게임을 시작하기 위해서 1 SABU를 전송합니다.");

        // 토큰 전송
        const transactionHash = await sendTokenToAddress("0xf4F2AF207618Bd639aA70eD9498A98CB8391BC26", '1', tokenInfo.options.address);
        // 토큰 전송 성공 시 동적 버튼 생성
        if (transactionHash) {
            console.log("게임을 시작합니다!");
            createNumberButtons();
        } else {
            console.log("Token sending failed.");
        }
    } catch (error) {
        console.error("Error:", error);
    }
}

// createNumberButtons 함수 정의
function createNumberButtons() {
    // 버튼 컨테이너 요소 가져오기
    const buttonContainer = document.getElementById('results');

    // 버튼 컨테이너가 존재하는지 확인
    if (!buttonContainer) {
        console.error("Button container not found");
        return;
    }

    // 블루 버튼 생성
    const blueButton = document.createElement('button');
    blueButton.id = 'playBlue';
    blueButton.textContent = 'Choice Blue';
    // 블루 버튼 이벤트 리스너 추가
    blueButton.addEventListener('click', async () => {
        await playCard(true); // 블루 선택 시 playCard 함수 호출
    });

    // 레드 버튼 생성
    const redButton = document.createElement('button');
    redButton.id = 'playRed';
    redButton.textContent = 'Choice Red';
    // 레드 버튼 이벤트 리스너 추가
    redButton.addEventListener('click', async () => {
        await playCard(false); // 레드 선택 시 playCard 함수 호출
    });

    // 버튼 컨테이너에 버튼 추가
    buttonContainer.innerHTML = '';
    buttonContainer.appendChild(blueButton);
    buttonContainer.appendChild(redButton);
}

// 이벤트 처리
document.getElementById('approveButton').addEventListener('click', async () => {
    await approveContract(); // 스마트 계약에 대한 토큰 인출 권한 부여
});

document.getElementById('withdrawButton').addEventListener('click', async () => {
    await withdrawTokens(); // 토큰을 지갑으로 전송
});

window.addEventListener('load', async () => {
    await getTokenBalance(); // 페이지 로드 시 토큰 잔액 표시
});

document.getElementById('refreshBalance').addEventListener('click', async () => {
    await getTokenBalance(); // 버튼 클릭 시 토큰 잔액 새로고침
});

// 토큰 잔액 가져오기
async function getTokenBalance() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    const account = await getAccount(); // 현재 사용자의 계정을 가져옴
    const contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS); // 스마트 계약과의 연결 생성

    // 사용자의 토큰 잔액 가져오기
    const balance = await contract.methods.getTokenBalance().call({ from: account });
    document.getElementById('balanceAmount').innerHTML = balance; // balanceAmount 요소에 토큰 잔액 업데이트
}

// 승자가 토큰에서 지갑을 빼내는 함수
async function withdrawTokens() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    const account = await getAccount(); // 현재 사용자의 계정을 가져옴
    const contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS); // 스마트 계약과의 연결 생성

    try {
        // 스마트 계약에 withdrawTokens 함수 호출
        await contract.methods.withdrawTokens().send({ from: account });
        console.log('Withdrawal successful'); // 인출이 성공한 경우 콘솔에 메시지 출력
    } catch (error) {
        console.error('Withdrawal failed:', error); // 인출이 실패한 경우 콘솔에 에러 메시지 출력
    }
}

document.getElementById('viewBalanceButton').addEventListener('click', async () => {
    await viewContractTokenBalance(); // 버튼 클릭 시 토큰 잔액 새로고침
});

async function viewContractTokenBalance() {
    if (networkCheck()) {
        // 네트워크가 일치하지 않으면 종료
        return;
    }
    await window.ethereum.send('eth_requestAccounts');
    window.web3 = new Web3(window.ethereum);
    
    const contract = new web3.eth.Contract(CONTRACT_ABI, CONTRACT_ADDRESS); // 스마트 계약과의 연결 생성
    const maxWinToken = await contract.methods.viewContractTokenBalance().call();
    document.getElementById('maxWinTokenbalance').innerHTML = maxWinToken; // maxTokenbalance 요소에 토큰 잔액 업데이트
}

