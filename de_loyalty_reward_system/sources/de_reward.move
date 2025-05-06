module de_reward::LoyaltySystem {

    use std::signer;
    use std::debug;
    use std::string::{Self, String};
    
    use aptos_std::table;

    use aptos_framework::object::{Self, ObjectCore};
    use aptos_framework::coin;
    use aptos_framework::managed_coin;

    //=========== Constants
    const ADMIN_OBJ_SEED: vector<u8> = b"ADMIN_LOYALTY_SYSTEM";
    //================//

    //=========== Error
    const E_NOT_AN_ADMIN: u64 = 1;
    const E_NO_OBJECT_FOUND: u64 = 2;
    const E_INSUFFICIENT_BAL: u64 = 3;
    const E_NO_OBJECT_CREATED: u64 = 4;
    //================//


    struct MvCoin{}

    struct RewardRegistry has store {
        recipient_addr: address,
        reward_coin: u64,
        expired_time: u64,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AdminRegistry has key {
        admin_addr: address,
        reward_registry: table::Table<u64, RewardRegistry>
    }


    // Helper function to print strings in a readable format
    fun print_string(message: String) {
        debug::print(&message);
    }

    // Helper function to convert byte string to String
    fun to_string(bytes: vector<u8>): String {
        string::utf8(bytes)
    }

    entry fun init_module(deployer: &signer){
        init_registry(deployer);
    }

    public fun init_registry(admin: &signer){
        managed_coin::initialize<MvCoin>(
            admin,
            b"Mv Coin",
            b"MV",
            6,
            false,
        );
        
        let constructor_ref = object::create_named_object(admin,ADMIN_OBJ_SEED);
        let object_signer = object::generate_signer(&constructor_ref);
        let admin_addr = signer::address_of(admin);

        move_to(&object_signer, AdminRegistry {
            admin_addr,
            reward_registry: table::new(),
        }); 

        register_user(&object_signer);
    }


    public entry fun register_user(user: &signer){
        managed_coin::register<MvCoin>(user);
    }

    public entry fun mint_coin(admin: &signer, amount: u64) acquires AdminRegistry{
        let admin_addr = signer::address_of(admin);


        let obj_address = get_object_account_address(admin_addr);
        is_object_registered(obj_address);

        let registry = borrow_global<AdminRegistry>(obj_address);

        // Validate user is admin
        assert!(registry.admin_addr == admin_addr, E_NOT_AN_ADMIN); 

        managed_coin::mint<MvCoin>(admin, obj_address, amount);

        let balance = coin::balance<MvCoin>(obj_address);
        debug::print(&balance);
    }

    public entry fun add_reword(admin: &signer, user_addr: address) {
        let admin_addr = signer::address_of(admin);

        let obj_address = get_object_account_address(admin_addr);
        is_object_registered(obj_address);

        let registry = borrow_global_mut<AdminRegistry>(obj_address);

        // Validate user is admin
        assert!(registry.admin_addr == admin_addr, E_NOT_AN_ADMIN);

        // let reward_registry =     


    }

    // =============== View ================ //

    #[view]
    public fun get_object_account_address(admin: address): address  {
        object::create_object_address(&admin, ADMIN_OBJ_SEED)
    }

    // ================================== //

    // =============== Utils ================ //


    public fun has_object_address(addr: address) {
        assert!(object::object_exists<ObjectCore>(addr), E_NO_OBJECT_CREATED);
    }

    public fun is_object_registered(addr: address) {
        assert!(exists<AdminRegistry>(addr), E_NO_OBJECT_FOUND);
    }

    // ================================== //

}