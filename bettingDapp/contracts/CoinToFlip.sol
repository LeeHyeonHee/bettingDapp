// SPDX-License-Identifier: MIT
pragma solidity >=0.4.21 <0.7.0;

contract CoinToFlip {

    uint constant MAX_CASE = 2; // for coin
    uint constant MIN_BET = 0.01 ether; // for coin
    uint constant MAX_BET = 10 ether; // for coin
    uint constant HOUSE_FEE_PERCENT = 5; // for coin
    uint constant HOUSE_MIN_FEE = 0.005 ether; // for coin

    address public owner;
    uint public lockedInBets;

    struct Bet {
        uint amount;
        uint8 numOfBetBit;
        uint placeBlockNumber; // Block number of Bet tx.
        //Bit mask representing winning bet outcomes
        // 0000 0010 for front side of coin, 50% chance
        // 0000 0001 for back side of coin, 50% chance
        // 0000 0011 for both sides, 100% chance - no reward!
        uint8 mask;
        address gambler; // Address of a gambler, used to pay out winning bets.
    }

    mapping (address => Bet) bets; //Bet book

    event Reveal(uint reveal);  // 1 or 2
    event Payment(address indexed beneficiary, uint amount);
    event FailedPayment(address indexed beneficiary, uint amount);

    constructor () public {
        owner = msg.sender;
    }

    //
    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    //Funds withdrawal to maintain the house
    function withdrawFunds(address beneficiary, uint withdrawAmount) external onlyOwner {
        require(withdrawAmount + lockedInBets <= address(this).balance, "larger than balance.");
        sendFunds(beneficiary,withdrawAmount);        
    }

    function sendFunds(address beneficiary, uint amount) private {
        if (beneficiary.send(amount)) {
            emit Payment(beneficiary, amount);
        } else {
            emit FailedPayment(beneficiary, amount);
        }
    }

    function kill() external onlyOwner {
        require(lockedInBets == 0, "All bets should be processed before self-destruct.");
        selfdestruct(owner);
    }

    function () public payable {}

    // Bet by player
    function placeBet (uint8 betMask) external payable {
        
        uint amount = msg.value;

        require(amount >= MIN_BET && amount <= MAX_BET, "Amount is out of range.");
        require(betMask > 0 && betMask < 256, "Mask should be 8 bit");

        Bet storage bet = bets[msg.sender]; // mapping bets(address => Bet)
        //Bet bet = bets[msg.sender];

        require(bet.gambler == address(0), "Bet should be empty state."); // can place a bet
        // if (bet.gambler == null) X // null 키워드가 없다   

        // count bet bit in the betMask
        // 0000 0011 number of bits = 2
        // 0000 0001 number of bits = 1
        uint8 numOfBetBit = countBits(betMask);

        bet.amount = amount;
        bet.numOfBetBit = numOfBetBit;
        bet.placeBlockNumber = block.number;
        bet.mask = betMask;
        bet.gambler = msg.sender;

        // need to lock possible winning amount to pay
        uint possibleWinningAmount = getWinningAmount(amount, numOfBetBit);
        lockedInBets += possibleWinningAmount;

        // Check whether house has enough ETH to pay the bet
        require(lockedInBets < address(this).balance, "Cannot afford to pay the bet.");
    }

    function getWinningAmount(uint amount, uint8 numOfBetBit) private pure returns (uint winningAmount) {
        require(0 < numOfBetBit && numOfBetBit < MAX_CASE, "Probability is out of range"); // 1

        uint houseFee = amount * HOUSE_FEE_PERCENT / 100;

        if(houseFee < HOUSE_MIN_FEE) {
            houseFee = HOUSE_MIN_FEE;
        }        

        // reward calculation is depends on your own idea
        uint reward = amount / (MAX_CASE + (numOfBetBit-1));

        winningAmount = (amount - houseFee) + reward;
    }


    // Reveal the coin by player
    function revealResult (uint8 seed) external {

        Bet storage bet = bets[msg.sender];
        uint amount = bet.amount;
        uint8 numOfBetBit = bet.numOfBetBit;
        uint placeBlockNumber = bet.placeBlockNumber;
        address gambler = bet.gambler;

        require(amount > 0, "Bet should be in an 'active' state");

        // should be called after placeBet
        require(block.number > placeBlockNumber, "revealResult in the same block as placeBet, or before.");

        // RNG(Random Number Generator) 
        bytes32 random = keccak256(abi.encodePacked(blockhash(block.number-seed), blockhash(placeBlockNumber))); 

        uint reveal = uint(random) % MAX_CASE; // 0 or 1

        uint winningAmmount = 0;
        uint possibleWinningAmount = 0;
        possibleWinningAmount = getWinningAmount(amount, numOfBetBit); 

        if ((2 ** reveal) & bet.mask != 0) {
            winningAmmount = possibleWinningAmount;
        }

        emit Reveal(2 ** reveal);

        if (winningAmmount > 0) {
            sendFunds(gambler, winningAmmount);
        }

        lockedInBets -= possibleWinningAmount;
        clearBet(msg.sender);
    }

    function clearBet(address player) private {
        Bet storage bet = bets[player];

        if (bet.amount > 0) { // for safety
            return;
        }    
        
        bet.amount = 0;
        bet.numOfBetBit = 0;
        bet.placeBlockNumber = 0;
        bet.mask = 0;
        bet.gambler = address(0); // NULL
    }

    function refundBet() external {
        
        Bet storage bet = bets[msg.sender];
        // Check that bet has been already mined.
        require(block.number > bet.placeBlockNumber, "refundBet in the same block as placeBet, or before.");

        uint amount = bet.amount;

        require(amount > 0, "Bet should be in an 'active' state");

        uint8 numOfBetBit = bet.numOfBetBit;

        // Send the refund.
        sendFunds(bet.gambler, amount);

        uint possibleWinningAmount;
        possibleWinningAmount = getWinningAmount(amount, numOfBetBit);

        lockedInBets -= possibleWinningAmount;
        clearBet(msg.sender);
    }

    function checkHouseFund() public view onlyOwner returns(uint) {
        return address(this).balance;       
    }

    function countBits(uint8 _num) internal pure returns (uint8) {
        uint8 count;
        while (_num > 0){
            count += _num & 1;
            _num >>= 1;
        }
        return count;
    }
}