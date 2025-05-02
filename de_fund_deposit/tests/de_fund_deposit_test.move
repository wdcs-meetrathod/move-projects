#[test_only]
module de_fund_deposit::test {
    use de_fund_deposit::FundDeposit;

    use std::signer;
    use std::string::{Self, String};
    use aptos_std::debug;
    use aptos_framework::aptos_coin::{Self,AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::account;

    const E_MINT_NOT_MATCH: u64 = 1;
    const E_USER_ALREADY_EXIST: u64 = 3;

    // Helper function to print strings in a readable format
    fun print_string(message: String) {
        debug::print(&message);
    }

    // Helper function to convert byte string to String
    fun to_string(bytes: vector<u8>): String {
        string::utf8(bytes)
    }

    #[test(aptos_framework = @0x1, admin = @0x40)]
    fun test_init_registry(aptos_framework: &signer, admin: &signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_user_register(aptos_framework: &signer, admin: &signer, user1:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    #[expected_failure(abort_code = 3)]
    fun test_user_re_register(aptos_framework: &signer, admin: &signer, user1:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);
        FundDeposit::register_user(user1);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41, user2 = @0x42, user3 = @0x43)]
    fun test_whitelist_user(aptos_framework: &signer, admin: &signer, user1:&signer,user2:&signer,user3:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);
        FundDeposit::register_user(user2);
        FundDeposit::register_user(user3);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let user3_addr = signer::address_of(user3);

        let users_vec = vector[user1_addr,user2_addr,user3_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec, true);

        let users_vec2 = vector[user3_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec2, false);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_user_deposit_fund(aptos_framework: &signer, admin: &signer, user1:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);

        let user1_addr = signer::address_of(user1);

        coin::register<AptosCoin>(user1);


        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);


        let users_vec = vector[user1_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec, true);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        FundDeposit::deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41, user2 = @0x42)]
    #[expected_failure(abort_code = 5)]
    fun test_deposit_fund_with_no_whitelisted_user(aptos_framework: &signer, admin: &signer, user1:&signer,user2:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);
        FundDeposit::register_user(user2);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);


        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);

        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user2_addr, coins);


        let users_vec = vector[user1_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec, true);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        FundDeposit::deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        print_string(to_string(b"[User2 balance before fund:]"));
        let user2_balance = FundDeposit::get_balance(user2_addr);
        debug::print<u64>(&user2_balance);
        FundDeposit::deposit_fund(user2, 1000);

        print_string(to_string(b"[User2 balance after fund:]"));
        let user2_balance = FundDeposit::get_balance(user2_addr);
        debug::print<u64>(&user2_balance);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    fun test_admin_withdraw_fund(aptos_framework: &signer, admin: &signer, user1:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);

        let user1_addr = signer::address_of(user1);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);


        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);


        let users_vec = vector[user1_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec, true);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        FundDeposit::deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance before:]"));
        debug::print<u64>(&admin_balance);

        FundDeposit::withdraw_fund(admin_addr, 1000);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance after:]"));
        debug::print<u64>(&admin_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x40, user1 = @0x41)]
    #[expected_failure(abort_code = 6)]
    fun test_user_withdraw_fund(aptos_framework: &signer, admin: &signer, user1:&signer) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        FundDeposit::init_registry(admin);

        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        FundDeposit::register_user(user1);

        let user1_addr = signer::address_of(user1);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);


        let coins = coin::mint<AptosCoin>(10000, &mint_cap);
        coin::deposit<AptosCoin>(user1_addr, coins);


        let users_vec = vector[user1_addr];
        FundDeposit::handle_whitelisted_user(admin, users_vec, true);

        print_string(to_string(b"[User1 balance before fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);
        FundDeposit::deposit_fund(user1, 1000);

        print_string(to_string(b"[User1 balance after fund:]"));
        let user1_balance = FundDeposit::get_balance(user1_addr);
        debug::print<u64>(&user1_balance);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance before:]"));
        debug::print<u64>(&admin_balance);

        FundDeposit::withdraw_fund(user1_addr, 1000);

        let admin_balance = coin::balance<AptosCoin>(admin_addr);
        print_string(to_string(b"[Admin AptosCoin Balance after:]"));
        debug::print<u64>(&admin_balance);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

}