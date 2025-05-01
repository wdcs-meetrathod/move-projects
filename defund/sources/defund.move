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
        campaign_address: address,
        creator_address: address,
        target_amount: u64
    }

    #[event]
    struct FundReceivedEvent has drop, store {
        campaign_id: u64,
        campaign_address: address,
        funder_address: address,
        amount: u64
    }

    #[event]
    struct FundWithdrawnEvent has drop, store {
        campaign_id: u64,
        campaign_address: address,
        creator_address: address,
        amount: u64   
    }

    struct PlatFormRegistry has key {
        campaign_counter: u64,
        campaign_address:table::Table<u64,address>,
    }

    /// Creator Profile
    struct CreatorProfile has key {
        name:String,
        campaigns:vector<u64>,
        campaign_caps: table::Table<u64,SignerCapability>,
        event_handle: event::EventHandle<CreatorRegisteredEvent>
    }

    /// Campaigns struct
    struct CampaignInfo has key {
        id: u64,
        creator_address: address,
        title: String,
        description: String,
        target_amount : u64,
        completed: bool,
        campaign_event_handle: event::EventHandle<CampaignsCreatedEvent>,
        funding_event_handle: event::EventHandle<FundReceivedEvent>,
        withdraw_event_handle: event::EventHandle<FundWithdrawnEvent>,
    }


    /// Initialize the platform - only one time
    public entry fun initialize_platform(account:&signer){
        let account_addr = signer::address_of(account);

        assert!(!exists<PlatFormRegistry>(account_addr),E_ALREADY_INITIALIZED);

        let platform = PlatFormRegistry {
         campaign_counter: 0,
         campaign_addresses: table::new(),
        };

        move_to(account,platform);
    }

    public entry fun register_creator(account:&signer,name:String){
        let addr = signer::address_of(account);

        assert!(!exists<CreatorProfile>(addr),E_ALREADY_INITIALIZED);

        let creator = CreatorProfile {
            name,
            campaigns:vector::empty<u64>(),
            campaign_caps: table::new();
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
        registry_address: address,
        title:String,
        description:String,
        target_amount: u64,
    ) acquires CreatorProfile, PlatFormRegistry{
        let creator_address = signer::address_of(creator);

        // Check is creator has exists
        assert!(exists<CreatorProfile>(creator_address),E_NOT_INITIALIZED);
        assert!(exists<PlatFormRegistry>(registry_address),E_NOT_INITIALIZED);

        let registry = borrow_global_mut<PlatFormRegistry>(registry_address);

        let campaign_id =  registry.campaign_counter;
        registry.campaign_counter = campaign_id + 1;

        let (resource_signer, resource_cap) = account::create_resource_account(creator);
        let resource_addr = signer::address_of(&resource_signer);

        coin::register<AptosCoin>(&resource_signer);

        let campaign = CampaignInfo {
            id: campaign_id,
            creator_address,
            title,
            description,
            target_amount,
            completed: false,
            campaign_event_handle: account::new_event_handle<CampaignCreatedEvent>(&resource_signer),
            funding_event_handle: account::new_event_handle<FundReceivedEvent>(&resource_signer),
            withdraw_event_handle: account::new_event_handle<FundWithdrawnEvent>(&resource_signer),
        };

        move_to(&resource_signer,campaign);

        table::add(&mut registry.campaigns_addresses,campaign_id,resource_addr);

        let profile = borrow_global_mut<CreatorProfile>(creator_address);
        vector::push_back(&mut profile.campaigns, campaign_id);
        table::add(&mut profile.campaign_caps,campaign_id,resource_cap);

        let campaign = borrow_global_mut<CampaignInfo>(resource_addr);

        event::emit_event(
            &mut campaign.campaign_event_handle,
            CampaignsCreatedEvent{
                title,
                campaign_id,
                creator_address,
                campaign_address: resource_addr,
                target_amount
            }
        );
    }

    public entry fun fund_campaign(
        funder:&signer,
        registry_address:address, 
        campaign_id:u64,
        amount:u64
        ) acquires PlatFormRegistry, CampaignInfo {

        let funder_addr = signer::address_of(funder);

        let registry = borrow_global<PlatFormRegistry>(registry_address);
        assert!(table::contains(&registry.campaign_address,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign_addr = *table::borrow(registry.campaign_addresses,campaign_id);    

        assert!(exists<CampaignInfo>(campaign_addr),E_CAMPAIGN_NOT_FOUND);
        let campaign = borrow_global_mut<CampaignInfo>(campaign_addr);

        coin::transfer<AptosCoin>(funder,campaign_addr,amount);

        let current_balance = coin::balance<AptosCoin>(campaign_addr);
        if(current_amount >= target_amount){
            campaign.completed = true;
        };
        
        event::emit_event(&mut campaign.funding_event_handle,FundReceivedEvent{
            campaign_id,
            campaign_address:campaign_addr,
            funder_address: funder_addr,
            amount
        });
    }

    public entry fun withdraw_fund(
        creator:&signer,
        registry_address:address,
        campaign_id:u64
        ) acquires PlatFormRegistry, CreatorProfile, CampaignInfo{

        let creator_addr = signer::address_of(creator);
        assert!(exists<CreatorProfile>(creator_addr),E_NOT_INITIALIZED);

        let creator_profile = borrow_global_mut<CreatorProfile>(creator_addr);
        assert!(table::contains(&creator_profile.campaign_caps,campaign_id),E_NOT_CREATOR);

        let registry = borrow_global<PlatFormRegistry>(registry_address);
        assert!(table::contains(&registry.campaign_addresses,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign_addr = *table::borrow(&registry.campaign_addresses,campaign_id);
        let campaign = borrow_global_mut<CreatorProfile>(&campaign_addr);
        assert!(campaign.completed,E_CAMPAIGN_NOT_COMPLETED);

        let resource_cap = table::borrow(&creator_profile.campaign_caps,campaign_id);
        let resource_signer = account::create_signer_with_capability(resource_cap);

        let amount = coin::balance<AptosCoin>(campaign_addr);

        coin::transfer<AptosCoin>(&resource_signer,creator_addr,amount);

        event::emit_event(
            &mut campaign.withdraw_event_handle,
            FundWithdrawEvent{
                campaign_id,
                campaign_address:campaign_addr,
                creator_address: creator_addr,
                amount
            }
        );
    }

    public fun get_campaign_details(
        registry_address: address,
        campaign_id:u64
        ):(address, String, String, u64, u64, bool)acquires DeFundPlatform{

        let registry = borrow_global<{PlatFormRegistry}>(registry_address);
        assert!(table::contains(&registry.campaign_addresses,campaign_id),E_CAMPAIGN_NOT_FOUND);

        let campaign_addr = *table::borrow(&registry.campaign_addresses,campaign_id);

        let campaign = borrow_global<CampaignInfo>(campaign_addr);    
        let current_balance = coin::balance<AptosCoin>(campaign_addr);

        (
            campaign.creator_address,
            campaign.title,
            campaign.description,
            campaign.target_amount,
             current_balance,
            campaign.completed

        )

    }

    public fun is_creator(addr:address):bool {
        exists<CreatorProfile>(addr)
    }

    public fun campaign_exists(
        registry_address,
        campaign_id: u64
    ):bool acquires PlatFormRegistry {

        let registry = borrow_global<PlatFormRegistry>(registry_address);
        table::contains(&registry.campaign_addresses,campaign_id);
    }

}