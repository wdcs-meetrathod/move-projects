module multisig_reward::MultiSig {

    use std::signer;
    use std::vector;
    
    use aptos_std::table;

    use aptos_framework::object::{Self, ExtendRef};
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;
    
    //  Constants
        const ADMIN_OBJ_SEED: vector<u8> = b"ADMIN_LOYALTY_SYSTEM";
        const DEFAULT_MINT_AMOUNT: u64 = 10000;
        const DEFAULT_THRESHOLD: u64 = 2;
    //

    //  Error Codes
        const E_NOT_AN_OWNER: u64 = 1;
        const E_NO_OBJECT_FOUND: u64 = 2;
        const E_INSUFFICIENT_BAL: u64 = 3;
        const E_NO_OBJECT_CREATED: u64 = 4;
        const E_INVALID_REWARD_USER: u64 = 5;
        const E_REWARD_EXPIRED: u64 = 6;
        const E_REWARD_DOES_NOT_EXIST: u64 = 7;
        const E_ADMIN_REGISTRY_NOT_FOUND: u64 = 8;
        const E_REWARD_REGISTRY_NOT_FOUND: u64 = 9;
        const E_INVALID_MINT_AMOUNT: u64 = 10;
        const E_NOT_SUPER_ADMIN: u64 = 11;
        const E_NOT_VALID_OWNER_LIMIT: u64 = 12;
        const E_VIOLATE_MIN_THRESHOLD: u64 = 13;
        const E_OWNER_ALREADY_EXISTS: u64 = 14;
        const E_OWNER_NOT_EXISTS: u64 = 15;
        const E_INVALID_REWARD_ID: u64 =16;
        const E_NOT_VALID_REWARD: u64 = 17;
        const E_EXPIRED_REGISTRY_NOT_EXIST: u64 = 18;
        const E_OWNER_HAS_ALREADY_APPROVED: u64 = 14;
    //

    struct MvCoin{}

    #[resource_group_member(group = object::ObjectGroup)]
    struct AdminRegistry has key {
        super_admin_addr: address,
        extend_ref: ExtendRef,
        owners: vector<address>,
        threshold: u64,
    }

    struct Reward has key, store {
        recipient_addr: address,
        approvals: vector<address>,
        amount: u64,
        expired_time: u64,
        is_claimed: bool
    }

    struct RewardRegistry has key, store {
        counter: u64,
        total_reward_amount: u64,
        rewards: table::Table<u64, Reward>,
    }

    struct ExpiredRewardRegistry has key, store {
        approvals: vector<address>,
        rewards: vector<u64>,
    }

    /**
        Initial module that only run at the time of deploy by super admin only    
    */
    fun init_module(super_admin: &signer){
        let super_admin_addr = signer::address_of(super_admin);
        is_super_admin(super_admin_addr);

        managed_coin::initialize<MvCoin>(
            super_admin,
            b"Mv Coin",
            b"Mv",
            6,
            false
        );

        let constructor_ref = object::create_named_object(super_admin, ADMIN_OBJ_SEED);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let obj_signer = object::generate_signer(&constructor_ref);
        
        move_to(&obj_signer, AdminRegistry {
            super_admin_addr,
            extend_ref,
            owners: vector::empty(),
            threshold: DEFAULT_THRESHOLD,
        });

        move_to(&obj_signer, RewardRegistry {
            counter: 0,
            total_reward_amount: 0,
            rewards: table::new(),
        }); 

        register_user(&obj_signer);
    }

    /**
        To register user for hold a MvCoin
    */
    public entry fun register_user(user: &signer){
        managed_coin::register<MvCoin>(user);
    }

    /**
        To mint the MvCoin
    */
    public entry fun mint_coin(super_admin: &signer, amount: u64) {
        let super_admin_addr = signer::address_of(super_admin);
        is_super_admin(super_admin_addr);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);

        managed_coin::mint<MvCoin>(super_admin, obj_address, amount);
        register_user(super_admin);
    }

    /**
        To add owners
    */
    public entry fun add_owner(super_admin: &signer, new_owner: address) acquires AdminRegistry{
        let super_admin_addr = signer::address_of(super_admin);
        is_super_admin(super_admin_addr);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);
        
        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);

        is_owner_already_exist(&admin_registry.owners, &new_owner);
        vector::push_back(&mut admin_registry.owners, new_owner);
    }

    /**
        To remove owners
    */
    public entry fun remove_owner(super_admin: &signer, owner_to_remove: address) acquires AdminRegistry{
        let super_admin_addr = signer::address_of(super_admin);
        is_super_admin(super_admin_addr);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);
        
        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        is_valid_threshold(vector::length(&admin_registry.owners) - 1, admin_registry.threshold);

        let (found, index) = vector::index_of(&admin_registry.owners, &owner_to_remove);
        assert!(found, E_OWNER_NOT_EXISTS);

        vector::remove(&mut admin_registry.owners, index);
    }

    /**
        To add the reward
        only valid once threshold owner approves
    */
    public entry fun propose_reward(owner: &signer, recipient_addr: address, amount: u64, expired_time: u64) acquires AdminRegistry, RewardRegistry {
        let owner_addr = signer::address_of(owner);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        assert!(is_owner(&admin_registry.owners , &owner_addr), E_NOT_AN_OWNER);
        is_valid_threshold(vector::length(&admin_registry.owners), admin_registry.threshold);

        check_sufficient_bal(obj_address, amount);
        is_reward_registry_exists(obj_address);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        let approvals = vector::empty();
        vector::push_back(&mut approvals, owner_addr);

        let reward = Reward {
            recipient_addr,
            approvals,
            amount,
            expired_time,
            is_claimed: false
        };

        let reward_counter = reward_registry.counter;
        table::add(&mut reward_registry.rewards, reward_counter, reward);
        reward_registry.counter += 1;
        reward_registry.total_reward_amount += amount;
    }

    /**
        To approve the reward by valid owner
    */
    public entry fun approve_reward(owner: &signer, reward_id: u64) acquires AdminRegistry, RewardRegistry{
        let owner_addr = signer::address_of(owner);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        assert!(is_owner(&admin_registry.owners , &owner_addr), E_NOT_AN_OWNER);

        is_reward_registry_exists(obj_address);
        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);

        is_valid_reward(&reward_registry.rewards, reward_id);
        let reward = table::borrow_mut(&mut reward_registry.rewards, reward_id);

        is_owner_already_approved(&reward.approvals, &owner_addr);
        vector::push_back(&mut reward.approvals, owner_addr);
    }

    /**
        To claim the reward
        once the approval reaches the required threshold
    */
    public entry fun claim_reward(user:&signer, reward_id: u64) acquires AdminRegistry, RewardRegistry{
        let user_addr = signer::address_of(user);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);
        is_reward_registry_exists(obj_address);

        let admin_registry = borrow_global<AdminRegistry>(obj_address); 
        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        assert!(table::contains(&reward_registry.rewards, reward_id), E_REWARD_DOES_NOT_EXIST);

        let reward = table::borrow_mut(&mut reward_registry.rewards, reward_id);
        has_valid_approval(vector::length(&reward.approvals), admin_registry.threshold);

        assert!(reward.recipient_addr == user_addr, E_INVALID_REWARD_USER);
        assert!(reward.expired_time >= timestamp::now_seconds(), E_REWARD_EXPIRED);
        
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);
        register_user(user);
        coin::transfer<MvCoin>(&obj_signer, user_addr, reward.amount);
        reward.is_claimed = true;
    }

    /**
        To propose withdraw expired reward
    */
    public entry fun propose_withdrawn(owner: &signer) acquires AdminRegistry, RewardRegistry, ExpiredRewardRegistry {
        let owner_addr = signer::address_of(owner);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);
        is_reward_registry_exists(obj_address);

        let admin_registry = borrow_global_mut<AdminRegistry>(obj_address);
        assert!(is_owner(&admin_registry.owners, &owner_addr), E_NOT_AN_OWNER);

        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);

        if(!is_expired_registry_exists(obj_address)){
            move_to(&obj_signer, ExpiredRewardRegistry{
                approvals: vector::empty(),
                rewards: vector::empty()
            });
        };

        let expired_registry = borrow_global_mut<ExpiredRewardRegistry>(obj_address);
        vector::push_back(&mut expired_registry.approvals, owner_addr);

        let i = 0;
        while (i < reward_registry.counter) {
            if (table::contains(&reward_registry.rewards, i)) {
                let reward = table::borrow_mut(&mut reward_registry.rewards, i);
            
                // Check if reward is expired and not claimed
                // reward.expired_time < timestamp::now_seconds() && 
                if (!reward.is_claimed) {
                    let (found, _) = vector::index_of(&expired_registry.rewards, &i);
                    if(!found){
                        vector::push_back(&mut expired_registry.rewards, i)
                    }
                };
            };
            i = i + 1;
        };
    }

    /**
        To approve the expired withdrawn.
    */
    public entry fun approve_withdrawn(owner: &signer) acquires AdminRegistry, ExpiredRewardRegistry{
        let owner_addr = signer::address_of(owner);
        let obj_address = get_object_account_address();
        
        is_admin_registry_exists(obj_address);
        is_expired_registry_exists(obj_address);

        let admin_registry = borrow_global<AdminRegistry>(obj_address);
        assert!(is_owner(&admin_registry.owners , &owner_addr), E_NOT_AN_OWNER);

        let expired_reward_registry = borrow_global_mut<ExpiredRewardRegistry>(obj_address);

        is_owner_already_approved(&expired_reward_registry.approvals, &owner_addr);
        vector::push_back(&mut expired_reward_registry.approvals, owner_addr);
    }

    /**
        To withdraw expired and approved by requires owner threshold.
    */
    public entry fun withdraw_expired_token(super_admin: &signer) acquires AdminRegistry, RewardRegistry, ExpiredRewardRegistry{
        let super_admin_addr = signer::address_of(super_admin);
        is_super_admin(super_admin_addr);

        let obj_address = get_object_account_address();
        is_admin_registry_exists(obj_address);
        is_reward_registry_exists(obj_address);
        is_expired_registry_exists(obj_address);

        let admin_registry = borrow_global<AdminRegistry>(obj_address);
        let expired_reward_registry = borrow_global<ExpiredRewardRegistry>(obj_address);
        let reward_registry = borrow_global_mut<RewardRegistry>(obj_address);

        is_valid_threshold(vector::length(&expired_reward_registry.approvals), admin_registry.threshold);
        let obj_signer = object::generate_signer_for_extending(&admin_registry.extend_ref);

        vector::for_each(expired_reward_registry.rewards, |i| {
            if (table::contains(&reward_registry.rewards, i)) {
                let reward = table::borrow_mut(&mut reward_registry.rewards, i);
                // Check if reward is expired and not claimed
                //reward.expired_time < timestamp::now_seconds() && 
                if (!reward.is_claimed) {
                    coin::transfer<MvCoin>(&obj_signer, super_admin_addr, reward.amount);
                    reward_registry.total_reward_amount -= reward.amount;
                    reward.amount = 0;
                };
            }
        });
    }



    //  View
        #[view]
        /**
            To get object address
        */
        public fun get_object_account_address(): address {
            object::create_object_address(&@super_admin, ADMIN_OBJ_SEED)
        }

        #[view]
        /**
            To get balance
        */
        public fun get_balance(addr:address): u64 {
            coin::balance<MvCoin>(addr)
        }
    //

    //  Utils

        /**
            To validate is admin registry exist
        */
        fun is_admin_registry_exists(addr:address){
            assert!(exists<AdminRegistry>(addr), E_ADMIN_REGISTRY_NOT_FOUND);
        }

        /**
            To validate is reward registry exist
        */
        fun is_reward_registry_exists(addr:address){
            assert!(exists<RewardRegistry>(addr), E_REWARD_DOES_NOT_EXIST);
        }

        /**
            To validate is reward registry exist
        */
        fun is_expired_registry_exists(addr:address): bool{
            exists<ExpiredRewardRegistry>(addr)
        }

        /**
            To validate user is super admin
        */
        fun is_super_admin(addr:address){
            assert!(addr == @super_admin, E_NOT_SUPER_ADMIN);
        }

        /**
            To  user is owner
        */
        fun is_owner(owners: &vector<address>, addr: &address): bool{
            vector::contains(owners, addr)
        }

        /**
            To ensure threshold limit is valid
        */    
        fun is_valid_threshold(owner_length: u64, threshold: u64){
            assert!(owner_length >= threshold, E_VIOLATE_MIN_THRESHOLD);
        }

        /**
            To ensure no duplicate owner
        */    
        fun is_owner_already_exist(owners: &vector<address> ,owner: &address){
           assert!(!vector::contains(owners, owner), E_OWNER_ALREADY_EXISTS);
        }

        /**
            To ensure user has sufficient balance
        */
        public fun check_sufficient_bal(addr:address, amount: u64){
            let current_bal = coin::balance<MvCoin>(addr);
            assert!(current_bal >= amount, E_INSUFFICIENT_BAL);
        }

        /**
            To ensure no duplicate approvals
        */
        public fun is_owner_already_approved(approvals: &vector<address>, addr: &address){
         

            let (found, _) = vector::index_of(approvals, addr);
            assert!(!found, E_OWNER_HAS_ALREADY_APPROVED)
        }

        /**
            To ensure approval reaches to the required threshold
        */
        public fun has_valid_approval(approvals: u64, threshold: u64){
            assert!(approvals >= threshold, E_NOT_VALID_REWARD);
        }

        /**
            To ensure user has sufficient balance
        */
        public fun is_valid_reward(reward_table: &table::Table<u64, Reward>, reward_id: u64){
            assert!(table::contains(reward_table, reward_id), E_INVALID_REWARD_ID);
        }
    //

    //  Tests
        #[test_only]
        use aptos_framework::account;

        #[test_only]    
        fun init_registry(framework: &signer, super_admin: &signer){
            account::create_account_for_test(signer::address_of(super_admin));
            coin::create_coin_conversion_map(framework);
            timestamp::set_time_has_started_for_testing(framework);
            let current_time = 10000000; // starting timestamp in microseconds
            timestamp::update_global_time_for_test_secs(current_time);

            let super_admin_addr = signer::address_of(super_admin);
            is_super_admin(super_admin_addr);

            managed_coin::initialize<MvCoin>(
                super_admin,
                b"Mv Coin",
                b"Mv",
                6,
                false
            );

            let constructor_ref = object::create_named_object(super_admin, ADMIN_OBJ_SEED);
            let extend_ref = object::generate_extend_ref(&constructor_ref);
            let obj_signer = object::generate_signer(&constructor_ref);

            move_to(&obj_signer, AdminRegistry {
                super_admin_addr,
                extend_ref,
                owners: vector::empty(),
                threshold: DEFAULT_THRESHOLD,
            });

            move_to(&obj_signer, RewardRegistry {
                counter: 0,
                total_reward_amount: 0,
                rewards: table::new(),
            }); 

            register_user(&obj_signer);
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_init_registry(framework: signer, super_admin:signer) {
            init_registry(&framework, &super_admin);
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_mint_coin(framework: signer, super_admin: signer) {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_add_owner(framework: signer, super_admin: signer) acquires AdminRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let user1 = account::create_account_for_test(@0x40);
            add_owner(&super_admin, signer::address_of(&user1));
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        #[expected_failure (abort_code = E_OWNER_ALREADY_EXISTS) ]
        fun test_add_duplicate_owner(framework: signer, super_admin: signer) acquires AdminRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let user1 = account::create_account_for_test(@0x40);

            add_owner(&super_admin, signer::address_of(&user1));
            add_owner(&super_admin, signer::address_of(&user1));
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_remove_owner(framework: signer, super_admin: signer) acquires AdminRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let user1 = account::create_account_for_test(@0x41);
            let user2 = account::create_account_for_test(@0x42);
            let user3 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&user1));
            add_owner(&super_admin, signer::address_of(&user2));
            add_owner(&super_admin, signer::address_of(&user3));
            remove_owner(&super_admin, signer::address_of(&user2));

        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        #[expected_failure (abort_code = E_OWNER_NOT_EXISTS) ]
        fun test_remove_non_exists_owner(framework: signer, super_admin: signer) acquires AdminRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let user1 = account::create_account_for_test(@0x41);
            let user2 = account::create_account_for_test(@0x42);
            let user3 = account::create_account_for_test(@0x43);
            let user4 = account::create_account_for_test(@0x44);

            add_owner(&super_admin, signer::address_of(&user1));
            add_owner(&super_admin, signer::address_of(&user2));
            add_owner(&super_admin, signer::address_of(&user3));
            remove_owner(&super_admin, signer::address_of(&user4));
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        #[expected_failure (abort_code = E_VIOLATE_MIN_THRESHOLD) ]
        fun test_violate_threshold(framework: signer, super_admin: signer) acquires AdminRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let user1 = account::create_account_for_test(@0x41);
            let user2 = account::create_account_for_test(@0x42);
            let user3 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&user1));
            add_owner(&super_admin, signer::address_of(&user2));
            add_owner(&super_admin, signer::address_of(&user3));

            remove_owner(&super_admin, signer::address_of(&user2));
            remove_owner(&super_admin, signer::address_of(&user3));
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_propose_reward(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        #[expected_failure (abort_code = E_VIOLATE_MIN_THRESHOLD) ]
        fun test_propose_reward_violate_threshold(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let user2 = account::create_account_for_test(@0x42);

            add_owner(&super_admin, signer::address_of(&owner));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_approve_reward(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            approve_reward(
                &owner2,
                0
            );
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_claim_reward(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            approve_reward(
                &owner2,
                0
            );

            claim_reward(
                &user2,
                0
            );
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        #[expected_failure (abort_code = E_NOT_VALID_REWARD) ]
        fun test_claim_reward_by_violated_threshold(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            claim_reward(
                &user2,
                0
            );
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_propose_withdrawn(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry, ExpiredRewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            approve_reward(
                &owner2,
                0
            );

            propose_withdrawn(&owner2);
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_approve_withdrawn(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry, ExpiredRewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner2,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            approve_reward(
                &owner,
                0
            );

            propose_withdrawn(&owner);
            approve_withdrawn(&owner2);
        }

        #[test(framework = @0x1, super_admin= @super_admin)]
        fun test_withdrawn_token(framework: signer, super_admin: signer) acquires AdminRegistry, RewardRegistry, ExpiredRewardRegistry {
            init_registry(&framework, &super_admin);

            mint_coin(&super_admin, DEFAULT_MINT_AMOUNT);
            assert!(get_balance(get_object_account_address()) == DEFAULT_MINT_AMOUNT , E_INVALID_MINT_AMOUNT);

            let owner = account::create_account_for_test(@0x41);
            let owner2 = account::create_account_for_test(@0x42);
            let user2 = account::create_account_for_test(@0x43);

            add_owner(&super_admin, signer::address_of(&owner));
            add_owner(&super_admin, signer::address_of(&owner2));

            let current_time_secs = timestamp::now_seconds();
            let thirty_minutes_in_seconds: u64 = 30 * 60;
            let expired_time = current_time_secs + thirty_minutes_in_seconds;

            propose_reward(
                &owner2,
                signer::address_of(&user2),
                1000,
                expired_time
            );

            approve_reward(
                &owner,
                0
            );

            propose_withdrawn(&owner);
            approve_withdrawn(&owner2);
            withdraw_expired_token(&super_admin);
            let balance = get_balance(signer::address_of(&super_admin));
            std::debug::print(&balance);
        }
    //
}