//  an example urbit star pool

pragma solidity ^0.4.24;

import 'openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol';

import './Constitution.sol';

//  Pool: simple ships-as-tokens contract
//
//    This contract displays a way to turn ships into tokens and vice versa.
//    It implements all functionality of an ERC20 token, and adds a few
//    additional functions to allow tokens to be obtained.
//
//    Using deposit(), an unbooted star can be transferred to this contract.
//    Upon receiving the star, this contract grants 2^16 tokens to the
//    sender. These token can be used like every other ERC20 token.
//    Using withdraw(), 2^16 tokens can be traded in to receive ownership
//    of one of the stars deposited into this contract.
//
contract Pool is StandardToken
{
  //  ERC20 token metadata
  //
  string constant public name = "Urbit Spark";
  string constant public symbol = "USP";
  uint256 constant public decimals = 18;
  uint256 constant public oneStar = 65536e18;

  //  ships: ships state data store
  //
  Ships public ships;

  //  assets: stars currently held in this pool
  //
  uint16[] public assets;

  //  assetIndexes: per star, (index + 1) in :assets
  //
  //    We delete assets by moving the last entry in the array to the
  //    newly emptied slot, which is (n - 1) where n is the value of
  //    assetIndexes[star].
  //
  mapping(uint16 => uint256) public assetIndexes;

  //  constructor(): register ships state data store
  //
  constructor(Ships _ships)
    public
  {
    ships = _ships;
  }

  //  getAllAssets(): return array of assets held by this contract
  //
  //    Note: only useful for clients, as Solidity does not currently
  //    support returning dynamic arrays.
  //
  function getAllAssets()
    view
    external
    returns (uint16[] allAssets)
  {
    return assets;
  }

  //  getAssetCount(): returns the number of assets held by this contract
  //
  function getAssetCount()
    view
    external
    returns (uint256 count)
  {
    return assets.length;
  }

  //  deposit(): add a star _star to the pool, receive a token in return
  //
  //    to be able to deposit, either of the following conditions must be
  //    satisfied:
  //
  //    (1) the caller is the owner of the star, the star has a key revision
  //    of zero, and this contract is configured as the star's transfer proxy
  //
  //    (2) the caller is the owner of the parent of the star, the star is
  //    inactive, and this contract is configured at the galaxy's spawn proxy
  //
  //    Note: in the if-else-if blocks below, any checks beyond the first
  //    practically don't matter. it would be fine to let the constitution
  //    revert in our stead, but we implement the checks anyway to make the
  //    required conditions clear through local contract code.
  //
  function deposit(uint16 _star)
    external
    isStar(_star)
  {
    //  case (1)
    //
    if ( //  :msg.sender must be the _star's owner
         //
         ships.isOwner(_star, msg.sender) &&
         //
         //  the _star may not have been used yet
         //
         !ships.hasBeenBooted(_star) &&
         //
         //  :this contract must be allowed to transfer the _star
         //
         ships.isTransferProxy(_star, this) )
    {
      //  transfer ownership of the _star to :this contract
      //
      Constitution(ships.owner()).transferShip(_star, this, true);
    }
    //
    //  case (2)
    //
    else if ( //  :msg.sender must be the _star's prefix's owner
              //
              ships.isOwner(ships.getPrefix(_star), msg.sender) &&
              //
              //  the _star must be inactive
              //
              !ships.isActive(_star) &&
              //
              //  :this contract must be allowed to spawn the _star
              //
              ships.isSpawnProxy(ships.getPrefix(_star), this) )
    {
      //  transfer ownership of the _star to :this contract
      //
      Constitution(ships.owner()).spawn(_star, this);
    }
    //
    //  if neither case is applicable, abort the transaction
    //
    else
    {
      revert();
    }

    //  update state to include the deposited star
    //
    assets.push(_star);
    assetIndexes[_star] = assets.length;

    //  mint a star token and grant it to the :msg.sender
    //
    totalSupply_ = totalSupply_.add(oneStar);
    balances[msg.sender] = balances[msg.sender].add(oneStar);
    emit Transfer(address(0), msg.sender, oneStar);
  }

  //  withdrawAny(): pay a token, receive the most recently deposited star
  //
  function withdrawAny()
    public
  {
    withdraw(assets[assets.length-1]);
  }

  //  withdraw(): pay a token, receive the star _star in return
  //
  function withdraw(uint16 _star)
    public
    isStar(_star)
  {
    //  make sure the :msg.sender has sufficient balance
    //
    require(balanceOf(msg.sender) >= oneStar);

    //  do some gymnastics to keep the list of owned assets gapless.
    //  delete the withdrawn asset from the list, then fill that gap with
    //  the list tail

    //  i: current index of _star in list of assets
    //
    uint256 i = assetIndexes[_star];

    //  we store index + 1, because 0 is the eth default value
    //
    require(i > 0);
    i--;

    //  copy the last item in the list into the now-unused slot
    //
    uint256 last = assets.length - 1;
    uint16 move = assets[last];
    assets[i] = move;

    //  delete the last item
    //
    delete(assets[last]);
    assets.length = last;
    assetIndexes[_star] = 0;

    //  we own one less star, so burn one token.
    //
    balances[msg.sender] = balances[msg.sender].sub(oneStar);
    totalSupply_ = totalSupply_.sub(oneStar);
    emit Transfer(msg.sender, address(0), oneStar);

    //  transfer ownership of the _star to :msg.sender
    //
    //    we don't need to reset because we already did so when
    //    transferring the ship to this contract.
    //
    Constitution(ships.owner()).transferShip(_star, msg.sender, false);
  }

  //  test if _star is a star, not a galaxy
  //
  modifier isStar(uint16 _star)
  {
    require(_star > 255);
    _;
  }
}
