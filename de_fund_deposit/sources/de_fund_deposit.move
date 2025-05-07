module de_fund_deposit::FundDeposit {

    use de_fund_deposit::errorCodes;
    
    use std::signer::address_of;
    use std::event;
    use std::vector;
    use std::debug;
    
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};

    const REGISTRY_SEED: vector<u8> = b"DE_FUND_DEPOSIT_REGISTRY";

    const E_UNAUTHORIZED:u64 = 5;
    const E_NOT_ADMIN:u64 = 6;

    #[event]
    struct ModuleInitEvent has drop, store {
        admin_addr: address,
        resource_addr: address,
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

    #[event]
    struct RefundEvent has drop, store {
        user_addr:address,
        amount:u64,
        remaining_fund:u64
    }

    struct FundRegistry has key{
        admin_addr: address,
        resource_address:address,
        resource_cap: SignerCapability,
        white_listed_addresses: vector<address>,
    }

    struct UserRegistry has key {
        user_addr: address,
        transferred_fund: u64
    }

    fun init_module(deployer:&signer){
        let (resource_signer, resource_signer_cap)  = account::create_resource_account(deployer,REGISTRY_SEED);
        let resource_address = address_of(&resource_signer);

        assert!(!exists<FundRegistry>(resource_address),errorCodes::fund_registry_already_exists());

        let admin_addr = address_of(deployer);
        move_to(&resource_signer, FundRegistry {
            admin_addr,
            resource_address,
            resource_cap: resource_signer_cap,
            white_listed_addresses: vector::empty(),
        });

        event::emit(ModuleInitEvent{
            admin_addr,
            resource_addr:resource_address
        });

        coin::register<AptosCoin>(&resource_signer);
    }

    public entry fun add_whitelist(admin:&signer, users:vector<address>) acquires FundRegistry{
        let admin_addr = address_of(admin);
        let resource_addr = get_registry_resource_address();

        is_registry_exists(resource_addr);
        let registry = borrow_global_mut<FundRegistry>(resource_addr);

        is_admin_user(registry.admin_addr, admin_addr);// Only admin can whitelist the users
        
        vector::for_each<address>(users, |user_addr: address| {
            vector::push_back(&mut registry.white_listed_addresses, user_addr);
        });
    }

    public entry fun remove_whitelist(admin:&signer, users:vector<address>) acquires FundRegistry, UserRegistry{
        let admin_addr = address_of(admin);

        let resource_addr = get_registry_resource_address();        
        is_registry_exists(resource_addr);

        let registry = borrow_global_mut<FundRegistry>(resource_addr);
        is_admin_user(registry.admin_addr, admin_addr);// Only admin can remove the white listed user

        vector::for_each<address>(users, |user_addr: address| {
            refund_removed_user_fund(resource_addr, &registry.resource_cap, user_addr);

            let (_, i) = vector::index_of<address>(&registry.white_listed_addresses, &user_addr);
            vector::remove<address>(&mut registry.white_listed_addresses, i);
        });
        
    }


    public entry fun deposit_fund(user:&signer, amount: u64) acquires UserRegistry, FundRegistry{
        let user_addr = address_of(user);

        let registry_addr = get_registry_resource_address();
        is_registry_exists(registry_addr);
        
        let registry = borrow_global<FundRegistry>(registry_addr);
        
        is_user_whitelisted(&registry.white_listed_addresses, &user_addr);
        has_sufficient_fund(user_addr, amount);

        coin::transfer<AptosCoin>(user, registry.resource_address, amount);

        if(exists<UserRegistry>(user_addr)){
            let user_registry = borrow_global_mut<UserRegistry>(user_addr);
            user_registry.transferred_fund = user_registry.transferred_fund + amount;
        }else{
            move_to(user, UserRegistry{
                user_addr,
                transferred_fund:0
            });
        };
        

        
        let total_fund = get_balance(registry.resource_address);

        event::emit(DepositEvent {
            user_addr,
            amount,
            total_fund,
        });
    }

    public entry fun withdraw_fund(admin_addr: address, amount: u64) acquires FundRegistry {
        let registry_addr = get_registry_resource_address();
        assert!(exists<FundRegistry>(registry_addr), errorCodes::fund_registry_not_found());

        let registry = borrow_global_mut<FundRegistry>(registry_addr);
        assert!(registry.admin_addr == admin_addr, errorCodes::unauthorized());

        let resource_signer = create_registry_resource_signer(&registry.resource_cap);
        let resource_addr = address_of(&resource_signer);
        has_sufficient_fund(resource_addr,amount);

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
    public fun get_registry_resource_address():address {
        account::create_resource_address(&@admin,REGISTRY_SEED)
    }
    
    #[view]
    public fun get_balance(addr:address): u64{
        coin::balance<AptosCoin>(addr)
    }

    // ======= Utils Functions ========== //

    public fun is_user_whitelisted(registry_addresses: &vector<address>, user_addr: &address) {
        let is_whitelisted = vector::contains<address>(registry_addresses, user_addr);
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

    public fun is_admin_user (admin_addr:address, user_addr:address){
        assert!(admin_addr == user_addr, errorCodes::unauthorized());
    }

    public fun create_registry_resource_signer(resource_cap: &SignerCapability):signer{
        account::create_signer_with_capability(resource_cap)
    }

    public fun refund_removed_user_fund(resource_addr :address,resource_cap :&SignerCapability, user_addr :address) acquires  UserRegistry{
        is_user_exists(user_addr);

        let user = borrow_global_mut<UserRegistry>(user_addr);
        let transferred_fund = user.transferred_fund;

        has_sufficient_fund(resource_addr,transferred_fund);

        let resource_balance = get_balance(resource_addr);
        let resource_signer = create_registry_resource_signer(resource_cap);
        coin::transfer<AptosCoin>(&resource_signer, user_addr, transferred_fund); // Refund the user's transferred fund

        event::emit(RefundEvent {
            user_addr,
            amount:transferred_fund,
            remaining_fund:resource_balance - transferred_fund,
        });
    }

    // Test
    #[test_only]
    use std::string::{Self, String};
    use aptos_framework::aptos_coin;
    

    #[test_only]
    // Helper function to print strings in a readable format
    fun print_string(message: String) {
        debug::print(&message);
    }
    #[test_only]
    // Helper function to convert byte string to String
    fun to_string(bytes: vector<u8>): String {
        string::utf8(bytes)
    }
    #[test_only]
    fun initialize_internal(deployer :&signer){
        let (resource_signer, resource_signer_cap)  = account::create_resource_account(deployer,REGISTRY_SEED);
        let resource_address = address_of(&resource_signer);

        assert!(!exists<FundRegistry>(resource_address),errorCodes::fund_registry_already_exists());

        let admin_addr = address_of(deployer);
        move_to(&resource_signer, FundRegistry {
            admin_addr,
            resource_address,
            resource_cap: resource_signer_cap,
            white_listed_addresses: vector::empty(),
        });

        coin::register<AptosCoin>(&resource_signer);
    }

    #[test(aptos_framework = @0x1, admin = @0x40)]
    fun test_initialize_internal(aptos_framework: &signer, admin: &signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41, user2 = @0x42, user3 = @0x43)]
    fun test_whitelist_user(aptos_framework: &signer, admin: &signer, user1:&signer,user2:&signer,user3:&signer) acquires FundRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);
        let user2_addr = address_of(user2);
        let user3_addr = address_of(user3);

        let users_vec = vector[user1_addr,user2_addr,user3_addr];
        add_whitelist(admin, users_vec);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_remove_whitelist_user(aptos_framework: &signer, admin: &signer, user1:&signer) acquires FundRegistry, UserRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);
        coin::register<AptosCoin>(user1);

        let users_vec = vector[user1_addr];
        add_whitelist(admin, users_vec);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        remove_whitelist(admin,users_vec);

        print_string(to_string(b"[User1 balance after re-fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_user_deposit_fund(aptos_framework: &signer, admin: &signer, user1:&signer) acquires FundRegistry, UserRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);
        coin::register<AptosCoin>(user1);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        let users_vec = vector[user1_addr];
        add_whitelist(admin, users_vec);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41, user2 = @0x42)]
    #[expected_failure(abort_code = E_UNAUTHORIZED)]
    fun test_deposit_fund_with_no_whitelisted_user(aptos_framework: &signer, admin: &signer, user1:&signer,user2:&signer) acquires FundRegistry, UserRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);
        let user2_addr = address_of(user2);

        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user2_addr, coins);


        let users_vec = vector[user1_addr];
        add_whitelist(admin, users_vec);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        print_string(to_string(b"[User2 balance before fund:]"));
        let user2_balance = get_balance(user2_addr);
        debug::print<u64>(&user2_balance);
        deposit_fund(user2, 1000);

        print_string(to_string(b"[User2 balance after fund:]"));
        let user2_balance = get_balance(user2_addr);
        debug::print<u64>(&user2_balance);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_admin_withdraw_fund(aptos_framework: &signer, admin: &signer, user1:&signer) acquires FundRegistry, UserRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        let users_vec = vector[user1_addr];
        add_whitelist(admin, users_vec);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance before:]"));
        debug::print<u64>(&admin_balance);

        withdraw_fund(admin_addr, 1000);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance after:]"));
        debug::print<u64>(&admin_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    #[expected_failure(abort_code = E_NOT_ADMIN)]
    fun test_user_withdraw_fund(aptos_framework: &signer, admin: &signer, user1:&signer) acquires FundRegistry, UserRegistry {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        initialize_internal(admin);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);

        let user1_addr = address_of(user1);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        let users_vec = vector[user1_addr];
        add_whitelist(admin, users_vec);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance before:]"));
        debug::print<u64>(&admin_balance);

        withdraw_fund(user1_addr, 1000);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance after:]"));
        debug::print<u64>(&admin_balance);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}