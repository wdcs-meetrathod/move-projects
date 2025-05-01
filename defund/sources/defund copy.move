module defund::defund {
    use std::signer;
    use std::vector;
    use std::string::{String};
    use aptos_std::table;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;

    const E_ALREADY_INITIALIZED:u64 = 1;
    const E_NOT_INITIALIZED:u64 = 2;
    const E_CAMPAIGN_NOT_FOUND:u64 = 3;
    const E_NOT_CREATOR:u64 = 4;
    const E_CAMPAIGN_NOT_COMPLETED:u64 = 5;

    #[event]
    struct CreatorRegisteredEvent has drop, store {
        creator_address: address,
        name: String
    }

    #[event]
    struct CampaignsCreatedEvent has drop, store {
        title: String,
        campaign_id: u64,
        creator_address: address,
        target_amount: u64
    }

    #[event]
    struct FundReceivedEvent has drop, store {
        campaign_id: u64,
        funder_address: address,
        amount: u64
    }

    #[event]
    struct FundWithdrawnEvent has drop, store {
        campaign_id: u64,
        creator_address: address,
        amount: u64   
    }

    /// Creator Profile
    struct CreatorProfile has key {
        name:String,
        campaigns:vector<u64>,
        event_handle: event::EventHandle<CreatorRegisteredEvent>
    }

    /// Campaigns struct
    struct Campaigns has store {
        id: u64,
        creator_address: address,
        title: String,
        description: String,
        target_amount : u64,
        current_amount: u64,
        completed: bool
    }

    /// Defund platform resource
    struct DeFundPlatform has key {
        campaign_counter: u64,
        campaigns: table::Table<u64,Campaigns>,
        campaign_event_handle: event::EventHandle<CampaignsCreatedEvent>,
        funding_event_handle: event::EventHandle<FundReceivedEvent>,
        withdraw_event_handle: event::EventHandle<FundWithdrawnEvent>,
    }

    /// Initialize the platform - only one time
    public entry fun initialize_platform(admin:&signer){
        let admin_addr = signer::address_of(admin);

        assert!(!exists<DeFundPlatform>(admin_addr),E_ALREADY_INITIALIZED);

        let platform = DeFundPlatform {
         campaign_counter: 0,
         campaigns: table::new(),
         campaign_event_handle: account::new_event_handle<CampaignsCreatedEvent>(admin),
         funding_event_handle: account::new_event_handle<FundReceivedEvent>(admin),
         withdraw_event_handle: account::new_event_handle<FundWithdrawnEvent>(admin),    
        };

        move_to(admin,platform);
    }

    public entry fun register_creator(account:&signer,name:String){
        let addr = signer::address_of(account);

        assert!(!exists<CreatorProfile>(addr),E_ALREADY_INITIALIZED);

        let creator = CreatorProfile {
            name,
            campaigns:vector::empty<u64>(),
            event_handle: account::new_event_handle<CreatorRegisteredEvent>(account),
        };

        event::emit_event(&mut creator.event_handle,CreatorRegisteredEvent {
            creator_address: addr,
            name
        });

        move_to(account,creator);

    }

    public entry fun create_campaign(
        creator:&signer,
        title:String,
        description:String,
        target_amount: u64,
    ) acquires CreatorProfile, DeFundPlatform{
        let creator_address = signer::address_of(creator);

        // Check is creator has exists
        assert!(exists<CreatorProfile>(creator_address),E_NOT_INITIALIZED);

        let platform = borrow_global_mut<DeFundPlatform>(@defund);

        let campaign_id =  platform.campaign_counter;
        platform.campaign_counter = campaign_id + 1;

        let campaign = Campaigns {
            id: campaign_id,
            creator_address,
            title,
            description,
            target_amount,
            current_amount: 0,
            completed: false
        };

        table::add(&mut platform.campaigns,campaign_id,campaign);

        let profile = borrow_global_mut<CreatorProfile>(creator_address);
        vector::push_back(&mut profile.campaigns, campaign_id);

        event::emit_event(
            &mut platform.campaign_event_handle,
            CampaignsCreatedEvent{
                title,
                campaign_id,
                creator_address,
                target_amount
            }
        );
    }

    public entry fun fund_campaign(funder:&signer, campaign_id:u64, amount:u64) acquires DeFundPlatform {
        let funder_addr = signer::address_of(funder);

        let platform = borrow_global_mut<DeFundPlatform>(@defund);

        assert!(table::contains(&platform.campaigns,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign = table::borrow_mut(&mut platform.campaigns,campaign_id);

        let coins = coin::withdraw<AptosCoin>(funder,amount);
        coin::deposit(@defund,coins);

        campaign.current_amount = campaign.current_amount + amount;

        if(campaign.current_amount >= campaign.target_amount){
            campaign.completed = true;
        };
        
        event::emit_event(&mut platform.funding_event_handle,FundReceivedEvent{
            campaign_id,
            funder_address: funder_addr,
            amount
        });
    }

    public entry fun withdraw_fund(admin:&signer, creator:&signer,campaign_id:u64) acquires DeFundPlatform{
        let creator_addr = signer::address_of(creator);

        let platform = borrow_global_mut<DeFundPlatform>(@defund);

        assert!(table::contains(&platform.campaigns,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign = table::borrow_mut(&mut platform.campaigns,campaign_id);

        assert!(campaign.creator_address == creator_addr,E_NOT_CREATOR);

        assert!(campaign.completed,E_CAMPAIGN_NOT_FOUND);

        let amount = campaign.current_amount;


        coin::transfer<AptosCoin>(admin,creator_addr,amount);

        event::emit_event(
            &mut platform.withdraw_event_handle, FundWithdrawnEvent {
                campaign_id,
                creator_address: creator_addr,
                amount,   
            }
        )

    }

    public fun get_campaign_details(campaign_id:u64):(address, String, String, u64, u64, bool)acquires DeFundPlatform{

        let platform = borrow_global<DeFundPlatform>(@defund);

        assert!(table::contains(&platform.campaigns,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign = table::borrow(&platform.campaigns,campaign_id);

        (
            campaign.creator_address,
            campaign.title,
            campaign.description,
            campaign.target_amount,
            campaign.current_amount,
            campaign.completed

        )

    }

    public fun is_creator(addr:address):bool {
        exists<CreatorProfile>(addr)
    }

}