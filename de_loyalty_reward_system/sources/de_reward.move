module de_reward::LoyaltySystem {

    use std::signer;
    use std::debug;
    use std::string::{Self, String};
    
    use aptos_std::table;

    use aptos_framework::object::{Self, ObjectCore, ExtendRef};
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;
    
    

    //=========== Constants
    const ADMIN_OBJ_SEED: vector<u8> = b"ADMIN_LOYALTY_SYSTEM";
    const DEFAULT_MINT_AMOUNT: u64 = 10000;
    //================//

    //=========== Error
    const E_NOT_AN_ADMIN: u64 = 1;
    const E_NO_OBJECT_FOUND: u64 = 2;
    const E_INSUFFICIENT_BAL: u64 = 3;
    const E_NO_OBJECT_CREATED: u64 = 4;
    const E_INVALID_REWARD_USER: u64 = 5;
    const E_REWARD_EXPIRED: u64 = 6;
    const E_REWARD_DOES_NOT_EXIST: u64 = 7;
    const E_ADMIN_REGISTRY_NOT_FOUND: u64 = 8;
    const E_REWARD_REGISTRY_NOT_FOUND: u64 = 9;
    const E_INVALID_MINT_AMOUNT: u64 = 10;
    //================//

    struct MvCoin{}

    #[resource_group_member(group = object::ObjectGroup)]
    struct AdminRegistry has key {
        admin_addr: address,
        extend_ref: ExtendRef
    }

    struct Reward has key, store {
        recipient_addr: address,
        amount: u64,
        expired_time: u64,
        is_claimed: bool
    }

    struct RewardRegistry has key, store {
        counter: u64,
        total_reward_amount: u64,
        rewards: table::Table<u64, Reward>,
    }


    // Helper function to print strings in a readable format
   public fun print_string(message: String) {
        debug::print(&message);
    }

    // Helper function to convert byte string to String
    public fun to_string(bytes: vector<u8>): String {
        string::utf8(bytes)
    }

    fun init_module(admin: &signer){
          managed_coin::initialize<MvCoin>(
            admin,
            b"Mv Coin",
            b"MV",
            6,
            false,
        );    

        let constructor_ref = object::create_named_object(admin,ADMIN_OBJ_SEED);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);
        let admin_addr = signer::address_of(admin);

        move_to(&object_signer, AdminRegistry {
            admin_addr,
            extend_ref,
        });

        move_to(&object_signer, RewardRegistry {
            counter: 0,
            total_reward_amount: 0,
            rewards: table::new(),
        }); 

        register_user(&object_signer);
    }

    public entry fun register_user(user: &signer){
        managed_coin::register<MvCoin>(user);
    }

    public entry fun mint_coin(admin: &signer, amount: u64) acquires AdminRegistry{
        let admin_addr = signer::address_of(admin);
        let obj_address = get_object_account_address();
        is_object_registered(obj_address);

        assert!(exists<AdminRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);
        let registry = borrow_global<AdminRegistry>(obj_address);

        // Validate user is admin
        assert!(registry.admin_addr == admin_addr, E_NOT_AN_ADMIN); 
        managed_coin::mint<MvCoin>(admin, obj_address, amount);
    }

    public entry fun add_reward(
        admin: &signer, 
        user_addr: address, 
        amount: u64, 
        expired_time: u64) 
        acquires AdminRegistry, RewardRegistry {
            
        let admin_addr = signer::address_of(admin);
        let obj_address = get_object_account_address();
        is_object_registered(obj_address);

        assert!(exists<AdminRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);
        assert!(exists<RewardRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);

        let registry = borrow_global<AdminRegistry>(obj_address);
        assert!(registry.admin_addr == admin_addr, E_NOT_AN_ADMIN); // Validate user is admin
        check_admin_object_sufficient_bal(obj_address, amount);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        let reward = Reward {
            recipient_addr: user_addr,
            amount,
            expired_time,
            is_claimed: false
        };

        let reward_counter = reward_registry.counter;
        table::add(&mut reward_registry.rewards, reward_counter, reward);
        reward_registry.counter += 1;
        reward_registry.total_reward_amount += amount;
    }

    public entry fun claim_reward(user:&signer, reward_id: u64) acquires AdminRegistry, RewardRegistry{
        let user_addr = signer::address_of(user);

        let obj_address = get_object_account_address();
        is_object_registered(obj_address);

        assert!(exists<AdminRegistry>(obj_address),E_ADMIN_REGISTRY_NOT_FOUND);
        assert!(exists<RewardRegistry>(obj_address),E_ADMIN_REGISTRY_NOT_FOUND);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        assert!(table::contains(&reward_registry.rewards, reward_id), E_REWARD_DOES_NOT_EXIST);

        let reward = table::borrow_mut(&mut reward_registry.rewards, reward_id);
        assert!(reward.recipient_addr == user_addr, E_INVALID_REWARD_USER);
        assert!(reward.expired_time >= timestamp::now_seconds(), E_REWARD_EXPIRED);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address); 
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);

        coin::transfer<MvCoin>(&obj_signer, user_addr, reward.amount);
        reward.is_claimed = true;
    }

    public entry fun withdraw_expired_token(admin: &signer) acquires AdminRegistry, RewardRegistry {
        let admin_addr = signer::address_of(admin);

        let obj_address = get_object_account_address();
        is_object_registered(obj_address);

        assert!(exists<AdminRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);
        assert!(exists<RewardRegistry>(obj_address), E_REWARD_REGISTRY_NOT_FOUND);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        assert!(admin_registry.admin_addr == admin_addr, E_NOT_AN_ADMIN);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);

        let i = 0;
        while (i < reward_registry.counter) {
            if (table::contains(&reward_registry.rewards, i)) {
            let reward = table::borrow_mut(&mut reward_registry.rewards, i);
            
            // Check if reward is expired and not claimed
            // reward.expired_time < timestamp::now_seconds() && 
            if (!reward.is_claimed) {
                
                coin::transfer<MvCoin>(&obj_signer, admin_addr, reward.amount);
                reward_registry.total_reward_amount -= reward.amount;
                reward.amount = 0;
            };
            };
            i = i + 1;
        };
    }

    public entry fun burn_expired_token(admin: &signer) acquires AdminRegistry, RewardRegistry {
        let admin_addr = signer::address_of(admin);

        let obj_address = get_object_account_address();
        is_object_registered(obj_address);

        assert!(exists<AdminRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);
        assert!(exists<RewardRegistry>(obj_address), E_ADMIN_REGISTRY_NOT_FOUND);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        assert!(admin_registry.admin_addr == admin_addr, E_NOT_AN_ADMIN);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);

        let i = 0;
        while (i < reward_registry.counter) {
            if (table::contains(&reward_registry.rewards, i)) {
            let reward = table::borrow_mut(&mut reward_registry.rewards, i);
            // Check if reward is expired and not claimed
            //reward.expired_time < timestamp::now_seconds() && 
            if (!reward.is_claimed) {
                coin::transfer<MvCoin>(&obj_signer,admin_addr, reward.amount);
                managed_coin::burn<MvCoin>(admin, reward.amount);
                reward_registry.total_reward_amount -= reward.amount;
                reward.amount = 0;
            };
        };
        i = i + 1;
        };
    }

    // =============== View ================ //

    #[view]
    public fun get_object_account_address(): address  {
        object::create_object_address(&@de_reward, ADMIN_OBJ_SEED)
    }

    #[view]
    public fun get_balance(addr:address): u64{
        coin::balance<MvCoin>(addr)
    }

    // ================================== //

    // =============== Utils ================ //


    public fun has_object_address(addr: address) {
        assert!(object::object_exists<ObjectCore>(addr), E_NO_OBJECT_CREATED);
    }

    public fun is_object_registered(addr: address) {
        assert!(exists<AdminRegistry>(addr), E_NO_OBJECT_FOUND);
    }

    public fun check_admin_object_sufficient_bal(addr:address, amount: u64){
        let current_bal = coin::balance<MvCoin>(addr);
        assert!(current_bal >= amount, E_INSUFFICIENT_BAL);
    }
    // ================================== //


    // =========== Test ============= //
    #[test_only]
    use aptos_framework::account;

    #[test_only]
    fun create_test_accounts():(signer, signer){
        let admin = account::create_account_for_test(@0x40);
        let user = account::create_account_for_test(@0x41);
        
        register_user(&admin);
        register_user(&user);

        (admin,user)
    }

    #[test_only]    
    fun init(framework: &signer, de_reward: &signer){
        account::create_account_for_test(signer::address_of(de_reward));
        coin::create_coin_conversion_map(framework);
        timestamp::set_time_has_started_for_testing(framework);
        let current_time = 10000000; // starting timestamp in microseconds
        timestamp::update_global_time_for_test_secs(current_time);

        init_registry(de_reward);
    }

    fun init_registry(admin: &signer){
        managed_coin::initialize<MvCoin>(
            admin,
            b"Mv Coin",
            b"MV",
            6,
            false,
        );    

        let constructor_ref = object::create_named_object(admin,ADMIN_OBJ_SEED);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);
        let admin_addr = signer::address_of(admin);

        move_to(&object_signer, AdminRegistry {
            admin_addr,
            extend_ref,
        });

        move_to(&object_signer, RewardRegistry {
            counter: 0,
            total_reward_amount: 0,
            rewards: table::new(),
        }); 

        register_user(&object_signer);
    }

    #[test(framework = @0x1, de_reward= @de_reward)]
    fun test_init_registry(framework: signer, de_reward:signer) {
        init(&framework, &de_reward);
    }

    #[test(framework = @0x1, de_reward= @de_reward)]
    fun test_mint_coin(framework: signer, de_reward: signer) acquires AdminRegistry {
        init(&framework, &de_reward);
        mint_coin(&de_reward, DEFAULT_MINT_AMOUNT);

        assert!(get_balance(
            get_object_account_address())
             == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);
    }

    #[test(framework = @0x1, de_reward = @de_reward)]
    fun test_add_reward(framework: signer, de_reward: signer) acquires AdminRegistry, RewardRegistry {
        
        init(&framework, &de_reward);
        mint_coin(&de_reward, DEFAULT_MINT_AMOUNT);
        
        let (user1, _) = create_test_accounts();
        let user1_addr = signer::address_of(&user1);
        let current_time_secs = timestamp::now_seconds();
        let thirty_minutes_in_seconds: u64 = 30 * 60;
        let expired_time = current_time_secs + thirty_minutes_in_seconds;
        
        add_reward(
           &de_reward,
           user1_addr,
           1000,
           expired_time
        );
    }

    #[test(framework = @0x1, de_reward = @de_reward)]
    fun test_claim_reward(framework: signer, de_reward: signer) acquires AdminRegistry, RewardRegistry {
        init(&framework, &de_reward);
        mint_coin(&de_reward, DEFAULT_MINT_AMOUNT);
        
        let (user1, _) = create_test_accounts();
        let user1_addr = signer::address_of(&user1);
        let current_time_secs = timestamp::now_seconds();
        let thirty_minutes_in_seconds: u64 = 30 * 60;
        let expired_time = current_time_secs + thirty_minutes_in_seconds;

        add_reward(
           &de_reward,
           user1_addr,
           1000,
           expired_time
        );

        print_string(to_string(b"[Object before claim:]"));
        let admin_balance = get_balance(get_object_account_address());
        debug::print<u64>(&admin_balance);

        print_string(to_string(b"[User1 balance before claim:]"));
        let user1_balance = get_balance(signer::address_of(&user1));
        debug::print<u64>(&user1_balance);

        claim_reward(
           &user1,
           0,
        );

        print_string(to_string(b"[Object after claim:]"));
        let admin_balance = get_balance(get_object_account_address());
        debug::print<u64>(&admin_balance);

        print_string(to_string(b"[User1 balance after claim:]"));
        let user1_balance = get_balance(signer::address_of(&user1));
        debug::print<u64>(&user1_balance);
    }

    #[test(framework = @0x1, de_reward = @de_reward)]
    fun test_withdrew_reward(framework: signer, de_reward: signer) acquires AdminRegistry, RewardRegistry {
        init(&framework, &de_reward);
        register_user(&de_reward);
        mint_coin(&de_reward, DEFAULT_MINT_AMOUNT);
        
        let (user1, user2) = create_test_accounts();
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);

        let current_time_secs = timestamp::now_seconds();
        let thirty_minutes_in_seconds: u64 = 30 * 60;
        let expired_time = current_time_secs + thirty_minutes_in_seconds;

        add_reward(
           &de_reward,
           user1_addr,
           1000,
           expired_time
        );

        add_reward(
           &de_reward,
           user2_addr,
           2000,
           expired_time
        );

        print_string(to_string(b"[Object before claim:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);

        print_string(to_string(b"[User1 balance before claim:]"));
        let user2_balance = get_balance(signer::address_of(&user2));
        debug::print<u64>(&user2_balance);

        claim_reward(
           &user2,
           1,
        );

        print_string(to_string(b"[Object after claim:]"));
        let admin_balance = get_balance(get_object_account_address());
        debug::print<u64>(&admin_balance);

        print_string(to_string(b"[User2 balance after claim:]"));
        let user2_balance = get_balance(signer::address_of(&user2));
        debug::print<u64>(&user2_balance);

        print_string(to_string(b"[Object before claim:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);

        print_string(to_string(b"[Admin before claim:]"));
        let admin_balance = get_balance(signer::address_of(&de_reward));
        debug::print<u64>(&admin_balance);

        withdraw_expired_token(
           &de_reward,
        );

        print_string(to_string(b"[Object after claim:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);

        print_string(to_string(b"[Admin after claim:]"));
        let admin_balance = get_balance(signer::address_of(&de_reward));
        debug::print<u64>(&admin_balance);
    }

    #[test(framework = @0x1, de_reward = @de_reward)]
    fun test_burn_reward(framework: signer, de_reward: signer) acquires AdminRegistry, RewardRegistry {
        init(&framework, &de_reward);
        register_user(&de_reward);
        mint_coin(&de_reward, DEFAULT_MINT_AMOUNT);
        
        let (user1, user2) = create_test_accounts();
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);

        let current_time_secs = timestamp::now_seconds();
        let thirty_minutes_in_seconds: u64 = 30 * 60;
        let expired_time = current_time_secs + thirty_minutes_in_seconds;

        add_reward(
           &de_reward,
           user1_addr,
           1000,
           expired_time
        );

        add_reward(
           &de_reward,
           user2_addr,
           2000,
           expired_time
        );

        print_string(to_string(b"[Object before claim:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);

        print_string(to_string(b"[User1 balance before claim:]"));
        let user2_balance = get_balance(signer::address_of(&user2));
        debug::print<u64>(&user2_balance);

        claim_reward(
           &user2,
           1,
        );

        print_string(to_string(b"[Object after claim:]"));
        let admin_balance = get_balance(get_object_account_address());
        debug::print<u64>(&admin_balance);

        print_string(to_string(b"[User2 balance after claim:]"));
        let user2_balance = get_balance(signer::address_of(&user2));
        debug::print<u64>(&user2_balance);

        print_string(to_string(b"[Object balance before burn:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);

        burn_expired_token(
           &de_reward,
        );

        print_string(to_string(b"[Object balance after burn:]"));
        let object_balance = get_balance(get_object_account_address());
        debug::print<u64>(&object_balance);
    }
}