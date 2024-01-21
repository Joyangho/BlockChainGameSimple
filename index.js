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

async function connectWallet() {
    if (window.ethereum) {
        if (window.ethereum.isTrust) {
            alert("Trust Wallet is not supported. Please use another wallet.", "", "warning");
            return;
        }
        await window.ethereum.send('eth_requestAccounts');
        window.web3 = new Web3(window.ethereum);
        if (window.web3._provider.networkVersion != Network) {
            alert("Please connect correct network", "", "warning");
        }

        var accounts = await web3.eth.getAccounts();
        WalletAddress = accounts[0];
        WalletBalance = await web3.eth.getBalance(WalletAddress);

        contract = new web3.eth.Contract(ABI, ADDRESS); 
        tokenBalance = await contract.methods.balanceOf(WalletAddress).call();

        tokenBalanceInEther = web3.utils.fromWei(tokenBalance);

        console.log("Token Balance:", tokenBalanceInEther);

        if (web3.utils.fromWei(WalletBalance) < 0.0001) {
            alert("You need more Ethereum");
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
        document.getElementById("result").innerHTML = "필요한 ETH: " + formattedResult + " + gas fee";
    } else {
        // 입력값이 비어있을 경우 결과를 0으로 설정
        document.getElementById("result").innerHTML = "필요한 ETH:";
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
