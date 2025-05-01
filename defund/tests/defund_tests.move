#[test_only]
module defund::defund_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::aptos_coin::AptosCoin;
    
    use defund::defund;

    const E_ALREADY_INITIALIZED:u64 = 1;

    public fun create_test_account (user:&signer){
        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
    }

    #[test(admin = @defund )]
    fun test_initialize_platform(admin:&signer){

        create_test_account(admin);

        defund::initialize_platform(admin);
    }

    #[test(admin = @defund )]
    #[expected_failure(abort_code= 1)]
    fun test_already_initialize_platform(admin:&signer){

        create_test_account(admin);

        defund::initialize_platform(admin);
        defund::initialize_platform(admin);
    }

    #[test(account = @defund )]
    fun test_register_creator(account:&signer){
        create_test_account(account);

        defund::register_creator(account,string::utf8(b"Meet"));
    }

    #[test(account = @defund )]
    #[expected_failure(abort_code= 1)]
    fun test_already_register_creator(account:&signer){

        create_test_account(account);

        defund::register_creator(account,string::utf8(b"Meet"));
        defund::register_creator(account,string::utf8(b"Meet"));
    }

    #[test(admin= @defund, creator = @0x321)]
    fun test_create_campaign(admin:&signer, creator:&signer){
        create_test_account(admin);
        defund::initialize_platform(admin);

        create_test_account(creator);
        defund::register_creator(creator,string::utf8(b"Meet"));

        let title = string::utf8(b"test");
        let description = string::utf8(b"test");
        let target_amount = 100;

        defund::create_campaign(creator, title, description, target_amount);
    }

    #[test(admin=@defund, creator = @0x123, funder = @0x456)]
    fun test_completeFlow(admin:&signer, creator:&signer, funder:&signer){

        let admin_addr = signer::address_of(admin);
        let creator_addr = signer::address_of(creator);
        let funder_addr = signer::address_of(funder);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(creator_addr);
        account::create_account_for_test(funder_addr);

        
        aptos_coin::initialize_for_test(admin);


        defund::register_creator(creator,string::utf8(b"Test Creator"));
        assert!(defund::is_creator(creator_addr),0);

        coin::register<AptosCoin>(funder);
        aptos_coin::mint(admin, funder_addr, 1000);

        defund::create_campaign(
            creator,
            string::utf8(b"Test Campaign"),
            string::utf8(b"Test Description"),
            500
        );

        defund::fund_campaign(funder,0,500);


        defund::withdraw_fund(admin,creator,0);

        assert!(coin::balance<AptosCoin>(creator_addr)==500,6);

        let (_,_,_,_,post_withdraw_amount,_) = defund::get_campaign_details(0);

        assert!(post_withdraw_amount == 0,7);
    }


}