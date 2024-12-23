module market::market {
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::bag::{Bag, Self};
    use sui::table::{Table, Self};
    use sui::event;
    use std::type_name;

    /// For when try to create a market with duplicated coin type.
    #[error]
    const EAlreadyExist: vector<u8> = b"Market already exist";
    /// For when amount paid does not match the expected.
    #[error]
    const EAmountIncorrect: vector<u8> = b"Amount incorrect";
    /// For when someone tries to delist without ownership.
    #[error]
    const ENotOwner: vector<u8> = b"You are not the owner";

    public struct MarketCreated has copy, drop{
        coin_type: type_name::TypeName,
        id: ID,
    }


    public struct MarketList has key,store{
        id: UID,
        list: Table<type_name::TypeName, bool>,
    }

    public struct MARKET has drop{}
    fun init(_otw:MARKET, ctx: &mut TxContext) {
        let market_list = MarketList {
            id: object::new(ctx),
            list: table::new(ctx),
        };
        transfer::share_object(market_list);
    }





    public struct Marketplace<phantom COIN> has key {
        id: UID,
        items: Bag,
        payments: Table<address, Coin<COIN>>
    }

    public struct Order has key, store {
        id: UID,
        ask: u64,
        owner: address,
    }

    /// Create a new shared Marketplace using `COIN`.
    public entry fun create_market<COIN>(market_list:&mut MarketList, ctx: &mut TxContext) {
        let coin_name = type_name::get<COIN>();
        assert!(!market_list.list.contains(coin_name), EAlreadyExist);

        let id = object::new(ctx);
        let items = bag::new(ctx);
        let payments = table::new<address, Coin<COIN>>(ctx);
        let marketplace =Marketplace<COIN> {  
            id, 
            items,
            payments
        };
        event::emit(MarketCreated{
            coin_type:coin_name,
            id: object::id(&marketplace),
        });
        transfer::share_object(marketplace);
    }

    /// Sell an item at the Marketplace.
    public entry fun place_order<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let item_id = object::id(&item);
        let mut listing = Order {
            ask,
            id: object::new(ctx),
            owner: ctx.sender(),
        };

        dof::add(&mut listing.id, true, item);
        marketplace.items.add(item_id, listing)
    }

    fun withdraw<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        ctx: &TxContext
    ): T {
        let Order {
            mut id,
            owner,
            ask: _,
        } = bag::remove(&mut marketplace.items, item_id);

        assert!(ctx.sender() == owner, ENotOwner);

        let item = dof::remove(&mut id, true);
        object::delete(id);
        item
    }

    public entry fun withdraw_and_take<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let item = withdraw<T, COIN>(marketplace, item_id, ctx);
        transfer::public_transfer(item, ctx.sender());
    }

    fun buy<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
    ): T {
        let Order {
            mut id,
            ask,
            owner
        } = marketplace.items.remove(item_id);

        assert!(ask == coin::value(&paid), EAmountIncorrect);

        // Check if there's already a Coin hanging and merge `paid` with it.
        // Otherwise attach `paid` to the `Marketplace` under owner's `address`.
        if (marketplace.payments.contains(owner)) {
            marketplace.payments.borrow_mut(owner).join(paid);
        } else {
            marketplace.payments.add(owner,paid);
        };
        let item = dof::remove(&mut id, true);
        object::delete(id);
        item
    }

    public entry fun buy_and_take<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(marketplace.buy<T, COIN>(item_id, paid), ctx.sender())
    }

    fun take_profits<COIN>(
        marketplace: &mut Marketplace<COIN>,
        ctx: &TxContext
    ): Coin<COIN> {
        table::remove<address, Coin<COIN>>(&mut marketplace.payments, ctx.sender())
    }

    public entry fun take_profits_and_keep<COIN>(
        marketplace: &mut Marketplace<COIN>,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(marketplace.take_profits(ctx), ctx.sender())
    }
}