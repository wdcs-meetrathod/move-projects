module de_fund_deposit::FundDeposit {

    use de_fund_deposit::errorCodes;
    
    use std::signer::address_of;
    use std::event;
    use std::vector;
    use std::debug;

    use aptos_std::table;
    
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;

    const REGISTRY_SEED: vector<u8> = b"DE_FUND_DEPOSIT_REGISTRY";

    #[event]
    struct ModuleInitEvent has drop, store {
        admin_addr: address,
        resource_addr: address,
    }

    #[event]
    struct UserInitEvent has drop, store {
        user_addr: address,
    }

    #[event]
    struct DepositEvent has drop, store {
        user_addr: address,
        amount:u64,
        total_fund:u64
    }

    #[event]
    struct WithdrawEvent has drop, store {
        admin_addr: address,
        amount:u64,
        remaining_fund:u64
    }

    struct FundRegistry has key {
        admin_addr: address,
        resource_address:address,
        resource_cap: SignerCapability,
        white_listed_addresses: table::Table<address, bool>,
    }

    struct UserRegistry has key {
        user_addr: address,
        transferred_fund: u64
    }

    public entry fun init_registry(admin:&signer){
        let (resource_signer, resource_signer_cap)  = account::create_resource_account(admin,REGISTRY_SEED);
        let resource_address = address_of(&resource_signer);

        assert!(!exists<FundRegistry>(resource_address),errorCodes::fund_registry_already_exists());

        let admin_addr = address_of(admin);
        move_to(&resource_signer, FundRegistry {
            admin_addr,
            resource_address,
            resource_cap: resource_signer_cap,
            white_listed_addresses: table::new(),
        });

        event::emit(ModuleInitEvent{
            admin_addr,
            resource_addr:resource_address
        });

            debug::print(&resource_address);
        coin::register<AptosCoin>(&resource_signer);
    }

    public entry fun register_user(user: &signer) acquires FundRegistry{
        let user_addr = address_of(user);
        assert!(!exists<UserRegistry>(user_addr),errorCodes::user_already_exists());

        let registry_addr = get_resource_address();

        assert!(!exists<FundRegistry>(user_addr),errorCodes::fund_registry_not_found());

        let registry = borrow_global_mut<FundRegistry>(registry_addr);

        table::add(&mut registry.white_listed_addresses, user_addr, false);

        move_to(user,UserRegistry {
            user_addr,
            transferred_fund: 0,
        });

        event::emit(UserInitEvent {
            user_addr
        });
    }

    public entry fun handle_whitelisted_user(admin:&signer, users:vector<address> ,do_whitelist:bool)acquires FundRegistry {
        let admin_addr = address_of(admin);

        let resource_addr = get_resource_address();        
        assert!(exists<FundRegistry>(resource_addr),errorCodes::fund_registry_not_found());

        let registry = borrow_global_mut<FundRegistry>(resource_addr);
        assert!(registry.admin_addr == admin_addr,errorCodes::unauthorized());

        let i = 0;

        while(i < vector::length(&users)){
            let user_addr  = *vector::borrow(&users,i);
            let user_ref = table::borrow_mut(&mut registry.white_listed_addresses, user_addr);
            *user_ref = do_whitelist;

            i = i + 1;
        }
    }

    public entry fun deposit_fund(user:&signer, amount: u64) acquires UserRegistry, FundRegistry{
        let user_addr = address_of(user);
        is_user_exists(user_addr);

        let registry_addr = get_resource_address();
        is_registry_exists(registry_addr);

        let registry = borrow_global<FundRegistry>(registry_addr);
        
        is_user_whitelisted(&registry.white_listed_addresses, user_addr);

        has_sufficient_fund(user_addr, amount);

        coin::transfer<AptosCoin>(user, registry.resource_address, amount);

        let user_registry = borrow_global_mut<UserRegistry>(user_addr);
        user_registry.transferred_fund = user_registry.transferred_fund + amount;

        
        let total_fund = get_balance(registry.resource_address);

        event::emit(DepositEvent {
            user_addr,
            amount,
            total_fund,
        });
    }

    public entry fun withdraw_fund(admin_addr: address, amount: u64) acquires FundRegistry {
        let registry_addr = get_resource_address();
        assert!(exists<FundRegistry>(registry_addr), errorCodes::fund_registry_not_found());

        let registry = borrow_global_mut<FundRegistry>(registry_addr);
        assert!(registry.admin_addr == admin_addr, errorCodes::unauthorized());

        let resource_signer = account::create_signer_with_capability(&registry.resource_cap);
        let resource_addr = address_of(&resource_signer);

        assert!(coin::balance<AptosCoin>(resource_addr) >= amount, errorCodes::insufficient_fund() );

        coin::transfer<AptosCoin>(&resource_signer, admin_addr, amount);

         let remaining_fund = get_balance(resource_addr);

        event::emit(WithdrawEvent{
            admin_addr,
            amount,
            remaining_fund,
        });
        
    }

    // ======= View Functions ========== //

    #[view]
    public fun get_resource_address():address {
        account::create_resource_address(&@admin,REGISTRY_SEED)
    }
    

    #[view]
    public fun get_balance(addr:address): u64{
        coin::balance<AptosCoin>(addr)
    }

    // ======= Utils Functions ========== //

    public fun is_user_whitelisted(registry_addresses: &table::Table<address,bool>, user_addr: address ) {
        assert!(table::contains(registry_addresses, user_addr), errorCodes::user_not_whitelisted());

        let is_whitelisted = *table::borrow(registry_addresses, user_addr);
        assert!(is_whitelisted, errorCodes::user_not_whitelisted());
    }

    public fun has_sufficient_fund(user_addr:address, amount:u64){
        assert!(coin::balance<AptosCoin>(user_addr) >= amount, errorCodes::insufficient_fund());
    }

    public fun is_registry_exists (addr:address) {
        assert!(exists<FundRegistry>(addr),errorCodes::fund_registry_not_found());
    }

    public fun is_user_exists(addr: address){
        assert!(exists<UserRegistry>(addr),errorCodes::user_not_exists());
    }

}