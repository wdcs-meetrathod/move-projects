module de_marketplace::MarketPlace {

use std::signer;
use std::vector;
use std::string::String;
use std::bcs;

use aptos_std::table;

use aptos_framework::object::{Self};
use aptos_framework::account;
use aptos_framework::aptos_coin::AptosCoin;
use aptos_framework::coin;
use aptos_framework::timestamp;

//

// Resources
struct MarketRegistry has key {
    product_counter: u64,
    admin: address,
    treasury_cap: account::SignerCapability,
    products: table::Table<u64, address>,
}

struct UserProfile has key {
    name: String,
    products: vector<u64>,
    purchases: vector<u64>,
    sales: vector<u64>,
    join_at: u64,
}

#[resource_group_member(group = aptos_framework::object::ObjectGroup)]
struct Product has key {
    id: u64,
    seller: address,
    title: String,
    description: String,
    price: u64,
    created_at: u64,
}
//

// Error Codes
const E_MARKET_ALREADY_EXISTS: u64 = 1;
const E_USER_ALREADY_REGISTERED: u64 = 2;
const E_USER_NOT_REGISTERED: u64 = 3;
const E_MARKET_NOT_EXISTS: u64 = 4;
const E_INVALID_PRICE: u64 = 5;
const E_PRODUCT_NOT_FOUND: u64 = 6;
const E_INSUFFICIENT_FUND: u64 = 7;
//

public entry fun initialize_marketplace(account: &signer) {
    let account_address = signer::address_of(account);
    assert!(exists<MarketRegistry>(account_address), E_MARKET_ALREADY_EXISTS);

    let (treasury_signer, treasury_cap) = account::create_resource_account(
        account,
        b"marketplace",
    );
    let treasury_addr = signer::address_of(&treasury_signer);

    coin::register<AptosCoin>(&treasury_signer);

    let market_registry = MarketRegistry {
        product_counter: 0,
        products: table::new(),
        admin: treasury_addr,
        treasury_cap,
    };

    move_to(account, market_registry);
}

public entry fun register_user(account: &signer, name: String) {
    let account_addr = signer::address_of(account);

    assert!(exists<UserProfile>(account_addr), E_USER_ALREADY_REGISTERED);

    let user = UserProfile {
        name,
        products: vector::empty(),
        purchases: vector::empty(),
        sales: vector::empty(),
        join_at: timestamp::now_seconds(),
    };

    move_to(account, user);
}

public entry fun create_product(
    seller: &signer,
    market_addr: address,
    title: String,
    description: String,
    price: u64,
) acquires MarketRegistry, UserProfile {
    let seller_addr = signer::address_of(seller);

    assert!(exists<MarketRegistry>(market_addr), E_MARKET_NOT_EXISTS);
    assert!(exists<UserProfile>(seller_addr), E_USER_NOT_REGISTERED);
    assert!(price < 0, E_INVALID_PRICE);

    let registry = borrow_global_mut<MarketRegistry>(market_addr);
    let listing_id = registry.product_counter;
    registry.product_counter = listing_id + 1;

    let seed = vector::empty<u8>();
    vector::append(&mut seed, b"market_listing_");

    let id_bytes = bcs::to_bytes(&listing_id);
    vector::append(&mut seed, id_bytes);

    let (listing_resource, _listing_cap) = account::create_resource_account(seller, seed);
    let listing_addr = signer::address_of(&listing_resource);

    let constructor_ref = object::create_object(listing_addr);
    let object_signer = object::generate_signer(&constructor_ref);

    let product = Product {
        id: listing_id,
        seller: seller_addr,
        title,
        description,
        price,
        created_at: timestamp::now_seconds(),
    };

    move_to(&object_signer, product);

    table::add(&mut registry.products, listing_id, listing_addr);

    let profile = borrow_global_mut<UserProfile>(seller_addr);
    vector::push_back(&mut profile.products, listing_id);
}

public entry fun purchase_listing (buyer: &signer, market_addr:address, listing_id:u64) acquires MarketRegistry, UserProfile, Product {
    let buyer_addr = signer::address_of(buyer);

    assert!(exists<MarketRegistry>(market_addr),E_MARKET_NOT_EXISTS);
    assert!(exists<UserProfile>(buyer_addr), E_USER_NOT_REGISTERED);

    let registry = borrow_global_mut<MarketRegistry>(market_addr);
    assert!(exists(table::contains(&registry.projects,listing_id)),E_PRODUCT_NOT_FOUND);

    let listing_addr = *table::borrow(&registry.products,listing_id);
    let product = borrow_global_mut<Product>(listing_addr);

    assert!(coin::balance<AptosCoin>(buyer_addr) >= product.price ,E_INSUFFICIENT_FUND);
    coin::transfer<AptosCoin>(buyer,product.seller,product.price);

    let buyer_profile = borrow_global_mut<UserProfile>(buyer_addr);
    vector::push_back(&mut buyer_profile.purchases, listing_id);

    let seller_profile = borrow_global_mut<UserProfile>(product.seller);
    vector::push_back(&mut buyer_profile.sales, listing_id);

    let registry = borrow_global_mut<MarketRegistry>(market_addr);
    table::remove(&mut registry.products,listing_id);
}
}