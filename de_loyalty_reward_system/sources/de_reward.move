module de_reward::LoyaltySystem {

    use std::signer;
    use std::debug;
    use std::string::{Self, String};
    

    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::object::{Self, ObjectCore};

    //=========== Constants
    const ADMIN_OBJ_SEED: vector<u8> = b"ADMIN_LOYALTY_SYSTEM";
    //================//

    //=========== Error
    const E_NOT_ADMIN: u64 = 1;
    const E_NO_OBJECT_FOUND: u64 = 2;
    const E_INSUFFICIENT_BAL: u64 = 3;
    const E_NO_OBJECT_CREATED: u64 = 4;
    //================//


    struct MvCoin has key{
        value: u64,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AdminRegistry has key {
        admin_addr: address,
        burn_cap: BurnCapability<MvCoin>,
        freeze_cap: FreezeCapability<MvCoin>,
        mint_cap: MintCapability<MvCoin>
    }


    // Helper function to print strings in a readable format
    fun print_string(message: String) {
        debug::print(&message);
    }

    // Helper function to convert byte string to String
    fun to_string(bytes: vector<u8>): String {
        string::utf8(bytes)
    }

    public entry fun init_registry(admin: &signer){
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MvCoin>(
            admin,
            string::utf8(b"Mv Coin"),
            string::utf8(b"MV"),
            6,
            false,
        );

        let constructor_ref = object::create_named_object(admin,ADMIN_OBJ_SEED);
        let object_signer = object::generate_signer(&constructor_ref);
        let admin_addr = signer::address_of(admin);

        move_to(&object_signer, AdminRegistry{
            admin_addr,
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        register_user(&object_signer);
    }

    public entry fun register_user(user: &signer){
        coin::register<MvCoin>(user);
    }

    public entry fun mint_coin(amount: u64){

        let (obj_singer, obj_address) = get_object_signer_and_address();
        is_object_registered(obj_address);

        let registry = borrow_global<AdminRegistry>(obj_address);

        coin::mint<MvCoin>(amount, &registry.mint_cap);

        let balance = coin::balance<MvCoin>(obj_address);
        debug::print(&balance);
    }

    // =============== View ================ //

    #[view]
    public fun get_object_address(admin:address): address  {
        object::create_object_address(@admin, ADMIN_OBJ_SEED)
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