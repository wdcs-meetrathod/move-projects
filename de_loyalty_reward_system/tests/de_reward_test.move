#[test_only]
module de_reward::Test {
    use de_reward::LoyaltySystem;

    use std::signer;
    

    use aptos_framework::account;    
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::managed_coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::aggregator_factory;


    fun create_test_accounts():(signer, signer){
        let admin = account::create_account_for_test(@0x40);
        let user = account::create_account_for_test(@0x41);

        (admin,user)
    }

    fun init(framework: &signer, de_reward: &signer){
        aptos_framework::account::create_account_for_test(signer::address_of(de_reward));
        aptos_framework::coin::create_coin_conversion_map(framework);
        LoyaltySystem::init_registry(de_reward);
    }

    #[test(framework = @0x1, de_reward= @de_reward)]
    fun test_init_registry(framework: signer, de_reward:signer) {
        init(&framework, &de_reward);
    }

    #[test(framework = @0x1, de_reward= @de_reward)]
    fun test_mint_coin(framework: signer, de_reward: signer) {
        init(&framework, &de_reward);
        LoyaltySystem::mint_coin(&de_reward, 10000);
    }
}