#[test_only]
module de_reward::Test {
    use de_reward::LoyaltySystem;

    use std::signer;
    

    use aptos_framework::account;    
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;

    fun create_test_accounts():(signer, signer){
        let admin = account::create_account_for_test(@de_reward);
        let user = account::create_account_for_test(@de_reward);

        (admin,user)
    }

    #[test]
    fun test_init_registry() {
        let (admin, _) = create_test_accounts();
        LoyaltySystem::init_registry(&admin);
    }

    #[test]
    fun test_mint_coin() {
        let (admin, _) = create_test_accounts();
        LoyaltySystem::init_registry(&admin);
        LoyaltySystem::register_user(&admin);

        LoyaltySystem::mint_coin(&admin, @de_reward, 10000);
    }
}