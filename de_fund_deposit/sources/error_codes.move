module de_fund_deposit::errorCodes {

    const E_FUND_REGISTRY_ALREADY_EXIST: u64 = 1;
    const E_FUND_REGISTRY_NOT_FOUND: u64 = 2;
    const E_USER_ALREADY_EXIST: u64 = 3;
    const E_USER_NOT_EXIST: u64 = 4;
    const E_USER_NOT_WHITELISTED: u64 = 5;
    const E_AUTHORIZED: u64 = 6;
    const INSUFFICIENT_FUND: u64 = 7;

    public fun fund_registry_already_exists():u64 {
        E_FUND_REGISTRY_ALREADY_EXIST
    }

    public fun fund_registry_not_found():u64 {
        E_FUND_REGISTRY_NOT_FOUND
    }

    public fun user_already_exists():u64 {
        E_USER_ALREADY_EXIST
    }

    public fun user_not_exists():u64 {
        E_USER_NOT_EXIST
    }

    public fun user_not_whitelisted():u64 {
        E_USER_NOT_WHITELISTED
    }

    public fun unauthorized():u64 {
        E_AUTHORIZED
    }

    public fun insufficient_fund():u64 {
        INSUFFICIENT_FUND
    }

    
}