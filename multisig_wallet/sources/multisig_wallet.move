module multisig::wallet {

    use std::signer;
    use std::vector;
    use std::event;

    use aptos_std::table;

    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::account::{Self, SignerCapability};


    // constant
    const REGISTRY_SEED:vector<u8> = b"MULTI_SIG_WALLET";

    //

    // errors
    const E_THRESHOLD_VIOLATES: u64 = 1;
    const E_WALLET_NOT_FOUND: u64 = 2;
    const E_NOT_VALID_SIGNER: u64 = 3;
    const E_INVALID_TRANSACTION: u64 = 4;
    const E_INSUFFICIENT_BALANCE: u64 = 5;
    const E_ALREADY_APPROVED: u64 = 6;

    //

    struct MultiSigWallet has key, store {
        resource_signer_cap: SignerCapability,
        signers: vector<address>,
        threshold: u64,
        balance: u64,
        transaction_count: u64,
        transactions: table::Table<u64, Transaction>,
    }

    struct Transaction has key, store {
        id: u64,
        to: address,
        sender: address,
        amount: u64,
        approvals: vector<address>,
        executed: bool,
    }

    #[event]
    struct ExecutedTransactionEvent has drop, store {
        to: address,
        amount: u64,
        sender: address
    }

    #[event]
    struct DepositTransactionEvent has drop, store {
        amount: u64,
        sender: address
    }

    #[event]
    struct ProposeTransactionEvent has drop, store {
        transaction_id: u64,
        sender: address,
        to: address,
        amount: u64
    }

    #[event]
    struct ApprovalTransactionEvent has drop, store {
        transaction_id :u64,
        approver: address,
    }

    public entry fun init_wallet(owner: &signer, signers: vector<address>, threshold: u64) {
        let (resource_signer, resource_signer_cap)  = account::create_resource_account(owner,REGISTRY_SEED);

        is_valid_threshold(vector::length(&signers), threshold);

        move_to(
            &resource_signer,
            MultiSigWallet {
                resource_signer_cap,
                signers,
                threshold,
                balance: 0,
                transactions: table::new(),
                transaction_count: 0,
            }
        );
        
        coin::register<AptosCoin>(&resource_signer);
    }

    public entry fun propose_fund(admin: &signer, multisig_addr: address, recipient_addr: address, amount: u64) acquires MultiSigWallet {
        is_multisig_wallet_exists(multisig_addr);

        let multisig_wallet = borrow_global_mut<MultiSigWallet>(multisig_addr);
        let admin_addr = signer::address_of(admin);

        is_valid_signer(&multisig_wallet.signers, &admin_addr);
        has_sufficient_bal(multisig_addr, amount);

        let transaction_id = multisig_wallet.transaction_count;       
        let transaction = Transaction {
            id: transaction_id,
            to: recipient_addr,
            sender: admin_addr,
            amount,
            approvals: vector[admin_addr],
            executed: false,
        };

        table::add(&mut multisig_wallet.transactions, transaction_id, transaction);
        multisig_wallet.transaction_count = transaction_id + 1;


        event::emit(
            ProposeTransactionEvent {
                transaction_id,
                sender:admin_addr,
                to: recipient_addr,
                amount
            }
        );
    }

    public entry fun approve_transaction(admin: &signer, multisig_addr: address, transaction_id: u64) acquires MultiSigWallet {
        is_multisig_wallet_exists(multisig_addr);

        let multisig_wallet = borrow_global_mut<MultiSigWallet>(multisig_addr);
        let admin_addr = signer::address_of(admin);

        is_valid_signer(&multisig_wallet.signers, &admin_addr);
        is_valid_transaction(&multisig_wallet.transactions, transaction_id);
        let transaction = table::borrow_mut(&mut multisig_wallet.transactions, transaction_id);

        is_already_approved(&transaction.approvals, &admin_addr);
        vector::push_back(&mut transaction.approvals, admin_addr);

        event::emit(
            ApprovalTransactionEvent {
                transaction_id,
                approver: admin_addr,
            }
        );


        if(is_reaches_to_threshold(multisig_wallet.threshold, vector::length(&transaction.approvals))){
            has_valid_threshold(multisig_wallet.threshold, vector::length(&transaction.approvals));

            let resource_signer = create_registry_resource_signer(&multisig_wallet.resource_signer_cap);
            coin::transfer<AptosCoin>(&resource_signer, transaction.to, transaction.amount);
            transaction.executed = true;

            event::emit(
                ExecutedTransactionEvent{
                    to: transaction.to,
                    amount: transaction.amount,
                    sender: transaction.sender
                }
            );

        }
    }

    #[view]
    public fun get_registry_resource_address():address {
        account::create_resource_address(&@multisig,REGISTRY_SEED)
    }

    #[view]
    fun get_balance(addr: address): u64 {
        coin::balance<AptosCoin>(addr)
    }
    //

    // utils
    fun is_valid_threshold(multisig_threshold: u64, threshold: u64) {
        assert!(threshold > 0 &&  multisig_threshold >= threshold, E_THRESHOLD_VIOLATES);
    }

    fun has_valid_threshold(multisig_threshold: u64, approvals: u64){
        assert!(approvals >= multisig_threshold, E_THRESHOLD_VIOLATES);
    }

    fun is_multisig_wallet_exists(addr: address) {
        assert!(exists<MultiSigWallet>(addr), E_WALLET_NOT_FOUND);
    }

    fun is_valid_signer(original_signers: &vector<address>, signer_addr: &address) {
        let (found, _) = vector::index_of(original_signers,signer_addr);
        assert!(found, E_NOT_VALID_SIGNER);
    }


    fun has_sufficient_bal(addr: address, amount: u64) {
        assert!(get_balance(addr) >= amount, E_INSUFFICIENT_BALANCE);
    }

    fun is_valid_transaction(transactions: &table::Table<u64,Transaction>, id: u64) {
        assert!(table::contains(transactions, id), E_INVALID_TRANSACTION);
    }   

    fun is_already_approved(approvals: &vector<address>, admin_addr: &address) {
        let (found, _) = vector::index_of(approvals, admin_addr);
        assert!(!found, E_ALREADY_APPROVED);
    }

    fun is_reaches_to_threshold(wallet_threshold: u64, threshold: u64): bool {
        wallet_threshold == threshold
    }

    public fun create_registry_resource_signer(resource_cap: &SignerCapability):signer{
        account::create_signer_with_capability(resource_cap)
    }

    //

    // Test

    #[test_only]
    fun get_test_users(): (signer, signer, signer){
        let user1 = account::create_account_for_test(@0x40);
        let user2 = account::create_account_for_test(@0x41);
        let user3 = account::create_account_for_test(@0x42);

        (user1, user2, user3)
    }

    #[test_only]
    fun get_test_singers(): vector<address> {
        let (user1, user2, user3) = get_test_users();
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);
        let user3_addr = signer::address_of(&user3);

        let signers = vector[user1_addr, user2_addr, user3_addr];
        signers
    }

    fun mint(user: &signer, mint_cap: &coin::MintCapability<AptosCoin>){
        coin::register<AptosCoin>(user);
        let coins = coin::mint<AptosCoin>(10000, mint_cap);
        coin::deposit<AptosCoin>(signer::address_of(user), coins);
    }

    #[test(aptos_framework= @aptos_framework)]
    fun init(aptos_framework: signer): (coin::BurnCapability<AptosCoin>, coin::MintCapability<AptosCoin>) acquires MultiSigWallet {
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(&aptos_framework);
        let deployer = account::create_account_for_test(@multisig);
        
        let signers = get_test_singers();
        init_wallet(&deployer, signers, 3);

        let multisig_wallet = borrow_global<MultiSigWallet>(get_registry_resource_address());
        let resource_signer = create_registry_resource_signer(&multisig_wallet.resource_signer_cap);
        mint(&resource_signer, &mint_cap);

        (burn_cap, mint_cap)
    }
    
    // #[test(aptos_framework= @aptos_framework)]
    // fun test_deposit_fund(aptos_framework:signer) {
    //     let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(&aptos_framework);
    //     let owner = account::create_account_for_test(@multisig);
    //     let signers = get_test_singers();
    //     init_wallet(&owner, signers, 2);
        
    //     let coins = coin::mint<AptosCoin>(1000, &mint_cap);
    //     coin::deposit<AptosCoin>(@multisig, coins);

    //     // deposit_fund(&user1, @multisig, 1000);

    //    std::debug::print(&get_balance(@multisig)); 

    //     coin::destroy_burn_cap(burn_cap);
    //     coin::destroy_mint_cap(mint_cap);
    // }

    #[test(aptos_framework= @aptos_framework)]
    fun test_propose_transaction(aptos_framework:signer) acquires MultiSigWallet {
        let (burn_cap, mint_cap) = init(aptos_framework);
        
        let admin = account::create_account_for_test(@0x40);
        let recipient = account::create_account_for_test(@0x41);

        propose_fund(&admin, get_registry_resource_address(), signer::address_of(&recipient), 1000);

        std::debug::print(&get_balance(get_registry_resource_address())); 

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework= @aptos_framework)]
    fun test_approve_transaction(aptos_framework:signer) acquires MultiSigWallet {
        let (burn_cap, mint_cap) = init(aptos_framework);
        
        let admin = account::create_account_for_test(@0x40);
        let recipient = account::create_account_for_test(@0x41);
        let recipient_addr = get_registry_resource_address();
        coin::register<AptosCoin>(&recipient);

        propose_fund(&admin, recipient_addr, signer::address_of(&recipient), 1000);

        let admin2 = account::create_account_for_test(@0x42);
        approve_transaction(&admin2, recipient_addr, 0);

        std::debug::print(&get_balance(get_registry_resource_address()));

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    //

}