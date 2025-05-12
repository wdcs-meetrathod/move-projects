module multisig::native_multisig {
    use std::signer;
    use std::vector;
    use std::string::{String};
    
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    
    struct WalletConfig has key {
        admin: address,
        transaction_count: u64,
    }
    
    struct TransactionRecord has key, store {
        transactions: vector<Transaction>,
    }
    
    struct Transaction has store {
        id: u64,
        recipient: address,
        amount: u64,
        executed: bool,
        description: String,
    }
    
    // Events
    #[event]
    struct TransferEvent has drop, store {
        transaction_id: u64,
        recipient: address,
        amount: u64,
        description: String,
    }
    
    public entry fun initialize(owner: &signer) {
        let owner_addr = signer::address_of(owner);
        
        // Register wallet config
        move_to(owner, WalletConfig {
            admin: owner_addr,
            transaction_count: 0,
        });
        
        move_to(owner, TransactionRecord {
            transactions: vector::empty<Transaction>(),
        });
        
        if (!coin::is_account_registered<AptosCoin>(owner_addr)) {
            coin::register<AptosCoin>(owner);
        }
    }
    
    public entry fun transfer_funds(
        wallet_signer: &signer,
        recipient: address,
        amount: u64,
        description: String,
    ) acquires WalletConfig, TransactionRecord {
        let wallet_addr = signer::address_of(wallet_signer);
        
        assert!(exists<WalletConfig>(wallet_addr), E_NOT_AUTHORIZED);
        
        assert!(coin::balance<AptosCoin>(wallet_addr) >= amount, E_INSUFFICIENT_BALANCE);
        
        let config = borrow_global_mut<WalletConfig>(wallet_addr);
        let record = borrow_global_mut<TransactionRecord>(wallet_addr);
        
        let tx_id = config.transaction_count;
        config.transaction_count = tx_id + 1;
        
        let transaction = Transaction {
            id: tx_id,
            recipient,
            amount,
            executed: true,
            description,
        };
        
        vector::push_back(&mut record.transactions, transaction);
        coin::transfer<AptosCoin>(wallet_signer, recipient, amount);
        
        // Emit event
        event::emit(
            TransferEvent {
                transaction_id: tx_id,
                recipient,
                amount,
                description,
            }
        );
    }
    
    #[view]
    public fun get_transaction_count(wallet_addr: address): u64 acquires WalletConfig {
        assert!(exists<WalletConfig>(wallet_addr), E_NOT_AUTHORIZED);
        borrow_global<WalletConfig>(wallet_addr).transaction_count
    }
    
    public entry fun change_admin(
        wallet_signer: &signer,
        new_admin: address,
    ) acquires WalletConfig {
        let wallet_addr = signer::address_of(wallet_signer);
        
        assert!(exists<WalletConfig>(wallet_addr), E_NOT_AUTHORIZED);
        
        let config = borrow_global_mut<WalletConfig>(wallet_addr);
        config.admin = new_admin;
    }
}