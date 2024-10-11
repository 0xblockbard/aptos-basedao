module dao_generator_addr::standard_dao {

    use std::event;
    use std::signer;
    use std::string::{String};
    use std::option::{Self, Option};

    use aptos_std::type_info;
    use aptos_std::smart_table::{Self, SmartTable};

    use aptos_framework::coin::{Self};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::fungible_asset::{Self, Metadata};

    // -----------------------------------
    // Seeds
    // -----------------------------------

    const APP_OBJECT_SEED : vector<u8>   = b"STANDARD_DAO";

    // -----------------------------------
    // Structs
    // -----------------------------------

    /// Dao Struct 
    struct Dao has key, store {
        creator: address,
        name: String,
        description: String,
        image_url: String,
        governance_token_metadata: Object<Metadata>,
    }

    /// DaoSigner Struct
    struct DaoSigner has key, store {
        extend_ref : object::ExtendRef,
    }

    /// VoteCount Struct
    struct VoteCount has store, drop {
        vote_type: u8,   // 0 -> NAY | 1 -> YAY | 2 -> PASS
        vote_count: u64
    }

    /// Proposal Struct
    struct Proposal has store {
        id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String,
        description: String,
        votes_yay: u64,
        votes_pass: u64,
        votes_nay: u64,
        total_votes: u64,
        success_vote_percent: u16,

        duration: u64,
        start_timestamp: u64,
        end_timestamp: u64,
        voters: SmartTable<address, VoteCount>, 

        result: String,
        executed: bool,

        // action data for transfer proposal 
        opt_transfer_recipient: option::Option<address>,
        opt_transfer_amount: option::Option<u64>,

        // action data for fa transfer proposal 
        opt_transfer_metadata: option::Option<Object<Metadata>>,

        // action data for coin transfer proposal 
        opt_coin_struct_name: option::Option<vector<u8>>,

        // action data for update proposal type
        opt_proposal_type: option::Option<String>, 
        opt_update_type: option::Option<String>,
        opt_duration: option::Option<u64>,
        opt_success_vote_percent: option::Option<u16>,
        opt_min_amount_to_vote: option::Option<u64>,
        opt_min_amount_to_create_proposal: option::Option<u64>,

        // action data for updating dao
        opt_dao_name: option::Option<String>,
        opt_dao_description: option::Option<String>,
        opt_dao_image_url: option::Option<String>
    }

    /// ProposalTable Struct
    struct ProposalTable has key, store {
        proposals : SmartTable<u64, Proposal>, 
    }

    /// ProposalRegistry Struct
    struct ProposalRegistry has key, store {
        proposal_to_proposer: SmartTable<u64, address>,
        next_proposal_id: u64
    }

    /// ProposalType Struct
    struct ProposalType has store, drop {
        duration: u64,
        success_vote_percent: u16,
        min_amount_to_vote: u64,
        min_amount_to_create_proposal: u64
    }

    /// ProposalTypeTable Struct
    struct ProposalTypeTable has key, store {
        proposal_types : SmartTable<String, ProposalType>, 
    }

    // -----------------------------------
    // Events
    // -----------------------------------

    #[event]
    struct NewProposalEvent has drop, store {
        proposal_id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String, 
        description: String,
        duration: u64 
    }

    #[event]
    struct NewVoteEvent has drop, store {
        proposal_id: u64,
        voter: address,
        vote_type: u8,
        vote_count: u64
    }

    #[event]
    struct ProposalExecutedEvent has drop, store {
        proposal_id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String, 
        description: String,
        result: String,
        executed: bool
    }


    // -----------------------------------
    // Errors
    // note: my preference for this convention for better clarity and readability
    // (e.g. ERROR_MISSING_TRANSFER_METADATA vs EMissingTransferMetadata)
    // -----------------------------------

    const ERROR_NOT_ADMIN : u64                             = 1;
    const ERROR_DAO_IS_ALREADY_SETUP: u64                   = 2;
    const ERROR_DAO_IS_PAUSED: u64                          = 3;
    const ERROR_INVALID_PROPOSAL_SUB_TYPE: u64              = 4;
    const ERROR_INCORRECT_CREATION_FEE : u64                = 4;
    const ERROR_INSUFFICIENT_GOVERNANCE_TOKENS : u64        = 5;
    const ERROR_PROPOSAL_EXPIRED : u64                      = 6;
    const ERROR_INVALID_TOKEN_METADATA: u64                 = 7;
    const ERROR_ALREADY_VOTED: u64                          = 8;
    const ERROR_PROPOSAL_HAS_NOT_ENDED: u64                 = 9;
    const ERROR_INVALID_UPDATE_TYPE: u64                    = 10;
    const ERROR_MISSING_TRANSFER_RECIPIENT: u64             = 11;
    const ERROR_MISSING_TRANSFER_AMOUNT: u64                = 12;
    const ERROR_MISSING_TRANSFER_METADATA: u64              = 13;
    const ERROR_SHOULD_HAVE_AT_LEAST_ONE_PROPOSAL_TYPE: u64 = 14;
    const ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED: u64 = 15;
    const ERROR_MISMATCH_COIN_STRUCT_NAME: u64              = 16;

    // -----------------------------------
    // Constants
    // -----------------------------------

    const CREATION_FEE: u64                                 = 0;     
    const FEE_RECEIVER: address                             = @fee_receiver_addr;

    // -----------------------------------
    // Init / Setup Functions
    // -----------------------------------

    /// Initializes the DAO with a fee transfer and stores the DAO's details.
    fun init_module(
        creator: &signer
    ) {

        let constructor_ref = object::create_named_object(
            creator,
            APP_OBJECT_SEED,
        );
        let extend_ref      = object::generate_extend_ref(&constructor_ref);
        let dao_signer      = &object::generate_signer(&constructor_ref);

        // Set DaoSigner
        move_to(dao_signer, DaoSigner {
            extend_ref,
        });

        // init ProposalRegistry struct
        move_to(dao_signer, ProposalRegistry {
            proposal_to_proposer: smart_table::new(),
            next_proposal_id: 0,
        });

        // init ProposalTypesTable struct with default proposal types
        let proposal_type_table = smart_table::new<String, ProposalType>();
        smart_table::add(&mut proposal_type_table, std::string::utf8(b"standard"), ProposalType {
            duration: 100_000_000,
            success_vote_percent: 30,
            min_amount_to_vote: 30_000_000,
            min_amount_to_create_proposal: 100_000_000
        });

        move_to(dao_signer, ProposalTypeTable {
            proposal_types: proposal_type_table
        });

    }

    // can only be called once
    public entry fun init_dao(
        creator: &signer, 
        dao_name: String, 
        dao_description: String, 
        dao_image_url: String, 
        governance_token_metadata: Object<Metadata>
    ) acquires DaoSigner {

        let dao_addr   = get_dao_addr();
        let dao_signer = get_dao_signer(dao_addr);

         // process dao creation fee 
        if(CREATION_FEE > 0){
            // transfer fee from creator to fee receiver
            coin::transfer<AptosCoin>(creator, FEE_RECEIVER, CREATION_FEE);
        };

        if(exists<Dao>(dao_addr)){
            abort ERROR_DAO_IS_ALREADY_SETUP
        };

        // set dao struct
        move_to(&dao_signer, Dao {
            creator: signer::address_of(creator),
            name: dao_name,
            description: dao_description,
            image_url: dao_image_url,
            governance_token_metadata
        });

    }

    // -----------------------------------
    // DAO Treasury Functions
    // -----------------------------------

    public entry fun deposit_fa_to_dao(
        depositor: &signer,
        amount: u64,
        token_metadata: Object<Metadata>
    ) {
        let dao_addr = get_dao_addr();

        // Transfer tokens from depositor to DAO
        primary_fungible_store::transfer(depositor, token_metadata, dao_addr, amount);
    }

    public entry fun deposit_coin_to_dao<CoinType>(
        depositor: &signer,
        amount: u64,
    ) acquires DaoSigner {
        
        let dao_addr    = get_dao_addr();
        let dao_signer  = get_dao_signer(dao_addr);

        if (!coin::is_account_registered<CoinType>(dao_addr)) {
            coin::register<CoinType>(&dao_signer);
        };

        // Withdraw the specified amount from the user's coin balance
        let coins = coin::withdraw<CoinType>(depositor, amount);
        
        // Deposit these coins back to the user's CoinStore, or another target
        coin::deposit<CoinType>(dao_addr, coins);
    }

    // -----------------------------------
    // General functions
    // -----------------------------------

    public entry fun create_fa_transfer_proposal(
        creator: &signer,
        title: String,
        description: String,
        proposal_type: String,
        opt_transfer_recipient: address,
        opt_transfer_amount: u64,
        opt_transfer_metadata: Object<Metadata>
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr            = get_dao_addr();
        let dao                 = borrow_global<Dao>(dao_addr);
        let creator_address     = signer::address_of(creator);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // check if creator has proposal table
        if (!exists<ProposalTable>(creator_address)) {
            move_to(creator, ProposalTable {
                proposals: smart_table::new(),
            });
        };
        let proposal_table      = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal type
        let proposal_type_obj = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        // verify sufficient governance token balance to create a proposal
        let creator_balance = primary_fungible_store::balance(signer::address_of(creator), dao.governance_token_metadata);
        assert!(creator_balance >= proposal_type_obj.min_amount_to_create_proposal, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // init proposal fields
        let proposal_id         = proposal_registry.next_proposal_id;
        let proposal_sub_type   = std::string::utf8(b"fa_transfer");
        let current_time        = aptos_framework::timestamp::now_seconds();
        let duration            = proposal_type_obj.duration;
        let end_timestamp       = current_time + duration;

        // Create a new proposal
        let proposal = Proposal {
            id: proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            votes_yay: 0,
            votes_pass: 0,
            votes_nay: 0,
            total_votes: 0,
            success_vote_percent: proposal_type_obj.success_vote_percent,
            duration,              
            start_timestamp: current_time,  
            end_timestamp: end_timestamp,   
            voters:  smart_table::new(),

            result: std::string::utf8(b"PENDING"),
            executed: false,
            
            // transfer data
            opt_transfer_recipient: option::some(opt_transfer_recipient),
            opt_transfer_amount: option::some(opt_transfer_amount),
            opt_transfer_metadata: option::some(opt_transfer_metadata),
            opt_coin_struct_name: option::none(),

            // proposal type data
            opt_proposal_type: option::none(),
            opt_update_type: option::none(),
            opt_duration: option::none(),
            opt_success_vote_percent: option::none(),
            opt_min_amount_to_vote: option::none(),
            opt_min_amount_to_create_proposal: option::none(),

            // update dao data
            opt_dao_name: option::none(),
            opt_dao_description: option::none(),
            opt_dao_image_url: option::none()

        };

        // emit event for new proposal
        event::emit(NewProposalEvent {
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title, 
            description,
            duration
        });

        // Store the proposal in the DAO's proposal table
        smart_table::add(&mut proposal_table.proposals, proposal_id, proposal);

        // update proposer registry and increment next proposal id
        proposal_registry.next_proposal_id = proposal_registry.next_proposal_id + 1;
        smart_table::add(&mut proposal_registry.proposal_to_proposer, proposal_id, creator_address);

    }

    
    public entry fun create_coin_transfer_proposal(
        creator: &signer,
        title: String,
        description: String,
        proposal_type: String,
        opt_transfer_recipient: address,
        opt_transfer_amount: u64,
        opt_coin_struct_name: vector<u8>
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr            = get_dao_addr();
        let dao                 = borrow_global<Dao>(dao_addr);
        let creator_address     = signer::address_of(creator);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // check if creator has proposal table
        if (!exists<ProposalTable>(creator_address)) {
            move_to(creator, ProposalTable {
                proposals: smart_table::new(),
            });
        };
        let proposal_table      = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal type
        let proposal_type_obj   = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        // verify sufficient governance token balance to create a proposal
        let creator_balance = primary_fungible_store::balance(signer::address_of(creator), dao.governance_token_metadata);
        assert!(creator_balance >= proposal_type_obj.min_amount_to_create_proposal, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // init proposal fields
        let proposal_id         = proposal_registry.next_proposal_id;
        let proposal_sub_type   = std::string::utf8(b"coin_transfer");
        let current_time        = aptos_framework::timestamp::now_seconds();
        let duration            = proposal_type_obj.duration;
        let end_timestamp       = current_time + duration;

        // Create a new proposal
        let proposal = Proposal {
            id: proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            votes_yay: 0,
            votes_pass: 0,
            votes_nay: 0,
            total_votes: 0,
            success_vote_percent: proposal_type_obj.success_vote_percent,
            duration,              
            start_timestamp: current_time,  
            end_timestamp: end_timestamp,   
            voters:  smart_table::new(),

            result: std::string::utf8(b"PENDING"),
            executed: false,
            
            // transfer data
            opt_transfer_recipient: option::some(opt_transfer_recipient),
            opt_transfer_amount: option::some(opt_transfer_amount),
            opt_transfer_metadata: option::none(),
            opt_coin_struct_name: option::some(opt_coin_struct_name),

            // proposal type data
            opt_proposal_type: option::none(),
            opt_update_type: option::none(),
            opt_duration: option::none(),
            opt_success_vote_percent: option::none(),
            opt_min_amount_to_vote: option::none(),
            opt_min_amount_to_create_proposal: option::none(),

            // update dao data
            opt_dao_name: option::none(),
            opt_dao_description: option::none(),
            opt_dao_image_url: option::none()

        };

        // emit event for new proposal
        event::emit(NewProposalEvent {
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title, 
            description,
            duration
        });

        // Store the proposal in the DAO's proposal table
        smart_table::add(&mut proposal_table.proposals, proposal_id, proposal);

        // update proposer registry and increment next proposal id
        proposal_registry.next_proposal_id = proposal_registry.next_proposal_id + 1;
        smart_table::add(&mut proposal_registry.proposal_to_proposer, proposal_id, creator_address);

    }


    public entry fun create_proposal_update_proposal(
        creator: &signer,
        title: String,
        description: String,
        proposal_type: String,
        opt_proposal_type: String, 
        opt_update_type: String,
        opt_duration: Option<u64>,
        opt_success_vote_percent: Option<u16>,
        opt_min_amount_to_vote: Option<u64>,
        opt_min_amount_to_create_proposal: Option<u64>
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr            = get_dao_addr();
        let dao                 = borrow_global<Dao>(dao_addr);
        let creator_address     = signer::address_of(creator);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // check if creator has proposal table
        if (!exists<ProposalTable>(creator_address)) {
            move_to(creator, ProposalTable {
                proposals: smart_table::new(),
            });
        };
        let proposal_table      = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal type
        let proposal_type_obj = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        // verify sufficient governance token balance to create a proposal
        let creator_balance = primary_fungible_store::balance(signer::address_of(creator), dao.governance_token_metadata);
        assert!(creator_balance >= proposal_type_obj.min_amount_to_create_proposal, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // init proposal fields
        let proposal_id         = proposal_registry.next_proposal_id;
        let proposal_sub_type   = std::string::utf8(b"proposal_update");
        let current_time        = aptos_framework::timestamp::now_seconds();
        let duration            = proposal_type_obj.duration;
        let end_timestamp       = current_time + duration;

        // validate correct update type
        if(!(opt_update_type == std::string::utf8(b"update") || opt_update_type == std::string::utf8(b"remove"))) {
            abort ERROR_INVALID_UPDATE_TYPE
        };

        // Create a new proposal
        let proposal = Proposal {
            id: proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            votes_yay: 0,
            votes_pass: 0,
            votes_nay: 0,
            total_votes: 0,
            success_vote_percent: proposal_type_obj.success_vote_percent,
            duration,
            start_timestamp: current_time,  
            end_timestamp: end_timestamp,   
            voters:  smart_table::new(),

            result: std::string::utf8(b"PENDING"),
            executed: false,
            
            // transfer data
            opt_transfer_recipient: option::none(),
            opt_transfer_amount: option::none(),
            opt_transfer_metadata: option:: none(),
            opt_coin_struct_name: option::none(),

            // proposal type data
            opt_proposal_type: option::some(opt_proposal_type),
            opt_update_type: option::some(opt_update_type),
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal,

            // update dao data
            opt_dao_name: option::none(),
            opt_dao_description: option::none(),
            opt_dao_image_url: option::none()

        };

        // emit event for new proposal
        event::emit(NewProposalEvent {
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title, 
            description,
            duration
        });

        // Store the proposal in the DAO's proposal table
        smart_table::add(&mut proposal_table.proposals, proposal_id, proposal);
        
        // update proposer registry and increment next proposal id
        proposal_registry.next_proposal_id = proposal_registry.next_proposal_id + 1;
        smart_table::add(&mut proposal_registry.proposal_to_proposer, proposal_id, creator_address);

    }


    public entry fun create_dao_update_proposal(
        creator: &signer,
        title: String,
        description: String,
        proposal_type: String,
        opt_dao_name: Option<String>,
        opt_dao_description: Option<String>,
        opt_dao_image_url: Option<String>
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr            = get_dao_addr();
        let dao                 = borrow_global<Dao>(dao_addr);
        let creator_address     = signer::address_of(creator);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // check if creator has proposal table
        if (!exists<ProposalTable>(creator_address)) {
            move_to(creator, ProposalTable {
                proposals: smart_table::new(),
            });
        };
        let proposal_table      = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal type
        let proposal_type_obj = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        // verify sufficient governance token balance to create a proposal
        let creator_balance = primary_fungible_store::balance(signer::address_of(creator), dao.governance_token_metadata);
        assert!(creator_balance >= proposal_type_obj.min_amount_to_create_proposal, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // init proposal fields
        let proposal_id         = proposal_registry.next_proposal_id;
        let proposal_sub_type   = std::string::utf8(b"dao_update");
        let current_time        = aptos_framework::timestamp::now_seconds();
        let duration            = proposal_type_obj.duration;
        let end_timestamp       = current_time + duration;

        // Create a new proposal
        let proposal = Proposal {
            id: proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            votes_yay: 0,
            votes_pass: 0,
            votes_nay: 0,
            total_votes: 0,
            success_vote_percent: proposal_type_obj.success_vote_percent,
            duration,
            start_timestamp: current_time,  
            end_timestamp: end_timestamp,   
            voters:  smart_table::new(),

            result: std::string::utf8(b"PENDING"),
            executed: false,
            
            // transfer data
            opt_transfer_recipient: option::none(),
            opt_transfer_amount: option::none(),
            opt_transfer_metadata: option:: none(),
            opt_coin_struct_name: option::none(),

            // proposal type data
            opt_proposal_type: option::none(),
            opt_update_type: option::none(),
            opt_duration: option::none(),
            opt_success_vote_percent: option::none(),
            opt_min_amount_to_vote: option::none(),
            opt_min_amount_to_create_proposal: option::none(),

            // update dao data
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url

        };

        // emit event for new proposal
        event::emit(NewProposalEvent {
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title, 
            description,
            duration
        });

        // Store the proposal in the DAO's proposal table
        smart_table::add(&mut proposal_table.proposals, proposal_id, proposal);
        
        // update proposer registry and increment next proposal id
        proposal_registry.next_proposal_id = proposal_registry.next_proposal_id + 1;
        smart_table::add(&mut proposal_registry.proposal_to_proposer, proposal_id, creator_address);

    }


    public entry fun create_standard_proposal(
        creator: &signer,
        title: String,
        description: String,
        proposal_type: String
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr            = get_dao_addr();
        let dao                 = borrow_global<Dao>(dao_addr);
        let creator_address     = signer::address_of(creator);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // check if creator has proposal table
        if (!exists<ProposalTable>(creator_address)) {
            move_to(creator, ProposalTable {
                proposals: smart_table::new(),
            });
        };
        let proposal_table      = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal type
        let proposal_type_obj = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        // verify sufficient governance token balance to create a proposal
        let creator_balance = primary_fungible_store::balance(signer::address_of(creator), dao.governance_token_metadata);
        assert!(creator_balance >= proposal_type_obj.min_amount_to_create_proposal, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // init proposal fields
        let proposal_id       = proposal_registry.next_proposal_id;
        let proposal_sub_type = std::string::utf8(b"standard");
        let current_time      = aptos_framework::timestamp::now_seconds();
        let duration          = proposal_type_obj.duration;
        let end_timestamp     = current_time + duration;

        // Create a new proposal
        let proposal = Proposal {
            id: proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            votes_yay: 0,
            votes_pass: 0,
            votes_nay: 0,
            total_votes: 0,
            success_vote_percent: proposal_type_obj.success_vote_percent,
            duration,
            start_timestamp: current_time,  
            end_timestamp: end_timestamp,   
            voters:  smart_table::new(),

            result: std::string::utf8(b"PENDING"),
            executed: false,
            
            // transfer data
            opt_transfer_recipient: option::none(),
            opt_transfer_amount: option::none(),
            opt_transfer_metadata: option:: none(),
            opt_coin_struct_name: option::none(),

            // proposal type data
            opt_proposal_type: option::none(),
            opt_update_type: option::none(),
            opt_duration: option::none(),
            opt_success_vote_percent: option::none(),
            opt_min_amount_to_vote: option::none(),
            opt_min_amount_to_create_proposal: option::none(),

            // update dao data
            opt_dao_name: option::none(),
            opt_dao_description: option::none(),
            opt_dao_image_url: option::none()

        };

        // emit event for new proposal
        event::emit(NewProposalEvent {
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title, 
            description,
            duration
        });

        // Store the proposal in the DAO's proposal table
        smart_table::add(&mut proposal_table.proposals, proposal_id, proposal);
        
        // update proposer registry and increment next proposal id
        proposal_registry.next_proposal_id = proposal_registry.next_proposal_id + 1;
        smart_table::add(&mut proposal_registry.proposal_to_proposer, proposal_id, creator_address);

    }


    public entry fun vote_for_proposal(
        voter: &signer,
        proposal_id: u64,
        vote_type: u8
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao {

        let dao_addr    = get_dao_addr();
        let dao         = borrow_global<Dao>(dao_addr);
        let voter_addr  = signer::address_of(voter);

        // get tables
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);
        let proposal_registry   = borrow_global_mut<ProposalRegistry>(dao_addr);

        // get creator address from registry
        let creator_address       = *smart_table::borrow(&proposal_registry.proposal_to_proposer, proposal_id);

        // get proposal from creator
        let proposal_table        = borrow_global_mut<ProposalTable>(creator_address);
        let proposal              = smart_table::borrow_mut(&mut proposal_table.proposals, proposal_id);

        // get proposal type
        let proposal_type_obj = smart_table::borrow(&proposal_type_table.proposal_types, proposal.proposal_type);

        // verify sufficient voter governance token balance to vote
        let voter_balance = primary_fungible_store::balance(voter_addr, dao.governance_token_metadata);
        assert!(voter_balance >= proposal_type_obj.min_amount_to_vote, ERROR_INSUFFICIENT_GOVERNANCE_TOKENS);

        // Ensure the proposal is still active and within the voting period
        let current_time   = aptos_framework::timestamp::now_seconds();
        assert!(current_time < proposal.end_timestamp, ERROR_PROPOSAL_EXPIRED);

        if (smart_table::contains(&proposal.voters, voter_addr)) {
            abort ERROR_ALREADY_VOTED
        } else {
            // Record the vote
            let vote_count = VoteCount {
                vote_type,
                vote_count: voter_balance,
            };

            // Add the voter and their vote to the voters' table
            smart_table::add(&mut proposal.voters, voter_addr, vote_count);
        };
        
        // Update the proposal votes based on the vote type
        if (vote_type == 1) {
            proposal.votes_yay = proposal.votes_yay + voter_balance;
        } else if (vote_type == 0) {
            proposal.votes_nay = proposal.votes_nay + voter_balance;
        } else if (vote_type == 2) {
            proposal.votes_pass = proposal.votes_pass + voter_balance;
        };

        // Update total votes
        proposal.total_votes = proposal.total_votes + voter_balance;

        // emit event for new vote event
        event::emit(NewVoteEvent {
            proposal_id,
            voter: voter_addr,
            vote_type,
            vote_count: voter_balance
        });

    }


    public entry fun execute_proposal(
        proposal_id: u64,
    ) acquires ProposalTable, ProposalRegistry, ProposalTypeTable, Dao, DaoSigner {

        let dao_addr    = get_dao_addr();
        let dao         = borrow_global_mut<Dao>(dao_addr);
        let dao_signer  = get_dao_signer(dao_addr);

        // get tables
        let proposal_registry   = borrow_global<ProposalRegistry>(dao_addr);
        let proposal_type_table = borrow_global_mut<ProposalTypeTable>(dao_addr);

        // get creator address from registry
        let creator_address       = *smart_table::borrow(&proposal_registry.proposal_to_proposer, proposal_id);

        // get proposal table from creator
        let proposal_table        = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal
        let proposal = smart_table::borrow_mut(
            &mut proposal_table.proposals, 
            proposal_id
        );

        // Ensure the proposal has ended
        let current_time   = aptos_framework::timestamp::now_seconds();
        assert!(current_time >= proposal.end_timestamp, ERROR_PROPOSAL_HAS_NOT_ENDED);

        // Calculate the required votes to pass
        let req_success_vote_percent = proposal.success_vote_percent;
        let total_supply             = option::destroy_some(fungible_asset::supply(dao.governance_token_metadata));
        let required_votes           = (total_supply * (req_success_vote_percent as u128)) / 10000;

        // execute proposal if sufficient votes gathered
        if ((proposal.votes_yay as u128) >= required_votes) {
            
            // Proposal passed
            if (proposal.proposal_sub_type == std::string::utf8(b"fa_transfer")) {
                
                let transfer_recipient: address          = option::destroy_some(proposal.opt_transfer_recipient);
                let transfer_amount: u64                 = option::destroy_some(proposal.opt_transfer_amount);
                let transfer_metadata: Object<Metadata>  = option::destroy_some(proposal.opt_transfer_metadata);

                primary_fungible_store::transfer(
                    &dao_signer, 
                    transfer_metadata,
                    transfer_recipient,
                    transfer_amount
                );

            };

            if (proposal.proposal_sub_type == std::string::utf8(b"coin_transfer")) {
                abort ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED
            };
            
            if (proposal.proposal_sub_type == std::string::utf8(b"proposal_update")) {

                // Handle proposal type updates
                let update_type: String        = option::destroy_some(proposal.opt_update_type);
                let proposal_type_name: String = option::destroy_some(proposal.opt_proposal_type);

                // add or update proposal type
                if (update_type == std::string::utf8(b"update")) {
                
                    let duration: u64                        = option::destroy_some(proposal.opt_duration);
                    let success_vote_percent: u16            = option::destroy_some(proposal.opt_success_vote_percent);
                    let min_amount_to_vote: u64              = option::destroy_some(proposal.opt_min_amount_to_vote);
                    let min_amount_to_create_proposal: u64   = option::destroy_some(proposal.opt_min_amount_to_create_proposal);

                    let new_proposal_type = ProposalType {
                        duration,
                        success_vote_percent,
                        min_amount_to_vote,
                        min_amount_to_create_proposal,
                    };

                    smart_table::upsert(
                        &mut proposal_type_table.proposal_types, 
                        proposal_type_name, 
                        new_proposal_type
                    );
                    
                }; 
                
                if (update_type == std::string::utf8(b"remove")) {

                    let proposal_type_count = smart_table::length(&proposal_type_table.proposal_types);
                    if(proposal_type_count > 1){
                        smart_table::remove(&mut proposal_type_table.proposal_types, proposal_type_name);
                    } else {
                        abort ERROR_SHOULD_HAVE_AT_LEAST_ONE_PROPOSAL_TYPE
                    }
                    
                };
            
            };
            
            if (proposal.proposal_sub_type == std::string::utf8(b"dao_update")) {
                
                if(option::is_some(&proposal.opt_dao_name)){
                    dao.name = option::destroy_some(proposal.opt_dao_name);
                };
                
                if(option::is_some(&proposal.opt_dao_description)){ 
                    dao.description = option::destroy_some(proposal.opt_dao_description);
                };
                
                if(option::is_some(&proposal.opt_dao_image_url)){   
                    dao.image_url   = option::destroy_some(proposal.opt_dao_image_url) 
                };

            };
            
            // Mark proposal as executed
            proposal.result   = std::string::utf8(b"SUCCESS");
            proposal.executed = true;

        } else {
            // Proposal did not pass; mark as executed without action
            proposal.result   = std::string::utf8(b"FAIL");
            proposal.executed = true;
        };

        // emit event for new proposal executed event
        event::emit(ProposalExecutedEvent {
            proposal_id,
            proposal_type: proposal.proposal_type,
            proposal_sub_type: proposal.proposal_sub_type,
            title: proposal.title,
            description: proposal.description,
            result: proposal.result,
            executed: proposal.executed
        });

    }


    public entry fun execute_coin_transfer_proposal<CoinType>(
        proposal_id: u64,
    ) acquires ProposalTable, ProposalRegistry, Dao, DaoSigner {

        let dao_addr    = get_dao_addr();
        let dao         = borrow_global_mut<Dao>(dao_addr);
        let dao_signer  = get_dao_signer(dao_addr);

        // get tables
        let proposal_registry   = borrow_global<ProposalRegistry>(dao_addr);

        // get creator address from registry
        let creator_address       = *smart_table::borrow(&proposal_registry.proposal_to_proposer, proposal_id);

        // get proposal table from creator
        let proposal_table        = borrow_global_mut<ProposalTable>(creator_address);

        // get proposal
        let proposal = smart_table::borrow_mut(
            &mut proposal_table.proposals, 
            proposal_id
        );

        // Ensure the proposal has ended
        let current_time   = aptos_framework::timestamp::now_seconds();
        assert!(current_time >= proposal.end_timestamp, ERROR_PROPOSAL_HAS_NOT_ENDED);

        // Calculate the required votes to pass
        let req_success_vote_percent = proposal.success_vote_percent;
        let total_supply             = option::destroy_some(fungible_asset::supply(dao.governance_token_metadata));
        let required_votes           = (total_supply * (req_success_vote_percent as u128)) / 10000;

        // execute proposal if sufficient votes gathered
        if ((proposal.votes_yay as u128) >= required_votes) {
            
            // Proposal passed
            if (proposal.proposal_sub_type == std::string::utf8(b"coin_transfer")) {
                
                let transfer_recipient: address          = option::destroy_some(proposal.opt_transfer_recipient);
                let transfer_amount: u64                 = option::destroy_some(proposal.opt_transfer_amount);
                let coin_struct_name: vector<u8>         = option::destroy_some(proposal.opt_coin_struct_name);

                let coin_type_info         = type_info::type_of<CoinType>();
                let given_coin_struct_name = type_info::struct_name(&coin_type_info);

                if(coin_struct_name == given_coin_struct_name){
                    coin::transfer<CoinType>(
                        &dao_signer, 
                        transfer_recipient,
                        transfer_amount
                    );
                } else {
                    abort ERROR_MISMATCH_COIN_STRUCT_NAME
                };

            } else {
                abort ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED
            };
            
            // Mark proposal as executed
            proposal.result   = std::string::utf8(b"SUCCESS");
            proposal.executed = true;

        } else {
            // Proposal did not pass; mark as executed without action
            proposal.result   = std::string::utf8(b"FAIL");
            proposal.executed = true;
        };

        // emit event for new proposal executed event
        event::emit(ProposalExecutedEvent {
            proposal_id,
            proposal_type: proposal.proposal_type,
            proposal_sub_type: proposal.proposal_sub_type,
            title: proposal.title,
            description: proposal.description,
            result: proposal.result,
            executed: proposal.executed
        });

    }


    // -----------------------------------
    // Views
    // -----------------------------------

    #[view]
    public fun get_dao_info(): (address, String, String, String, Object<Metadata>) acquires Dao {
        let dao_addr = get_dao_addr();
        let dao      = borrow_global<Dao>(dao_addr);
        (dao.creator, dao.name, dao.description, dao.image_url, dao.governance_token_metadata)
    }


    #[view]
    public fun get_next_proposal_id() : (u64) acquires ProposalRegistry {
        let dao_addr            = get_dao_addr();
        let proposal_registry   = borrow_global<ProposalRegistry>(dao_addr);
        (proposal_registry.next_proposal_id)
    }


    #[view]
    public fun get_proposal_type_info(proposal_type: String): (u64, u16, u64, u64) acquires ProposalTypeTable {
        let dao_addr            = get_dao_addr();
        let proposal_type_table = borrow_global<ProposalTypeTable>(dao_addr);

        // find the proposal type by name
        let proposal_type_ref = smart_table::borrow(&proposal_type_table.proposal_types, proposal_type);

        (
            proposal_type_ref.duration, 
            proposal_type_ref.success_vote_percent, 
            proposal_type_ref.min_amount_to_vote, 
            proposal_type_ref.min_amount_to_create_proposal
        )
    }


    #[view]
    public fun get_proposal_info(proposal_id: u64): (String, String, String, String, u64, u64, u64, u64, u16, u64, u64, u64, String, bool) acquires ProposalRegistry, ProposalTable {
        
        let dao_addr       = get_dao_addr();
        
        // get tables
        let proposal_registry   = borrow_global<ProposalRegistry>(dao_addr);

        // get creator address from registry
        let creator_address       = *smart_table::borrow(&proposal_registry.proposal_to_proposer, proposal_id);

        // get proposal table from creator
        let proposal_table        = borrow_global<ProposalTable>(creator_address);

        // find the proposal by id
        let proposal_ref = smart_table::borrow(&proposal_table.proposals, proposal_id);

        // return proposal fields
        (
            proposal_ref.proposal_type,
            proposal_ref.proposal_sub_type,
            proposal_ref.title,
            proposal_ref.description,

            proposal_ref.votes_yay,
            proposal_ref.votes_pass,
            proposal_ref.votes_nay,
            proposal_ref.total_votes,
            proposal_ref.success_vote_percent,

            proposal_ref.duration,
            proposal_ref.start_timestamp,
            proposal_ref.end_timestamp,
            
            proposal_ref.result,
            proposal_ref.executed
        )
    }

    // -----------------------------------
    // Helpers
    // -----------------------------------

    fun get_dao_addr(): address {
        object::create_object_address(&@dao_generator_addr, APP_OBJECT_SEED)
    }

    fun get_dao_signer(dao_addr: address): signer acquires DaoSigner {
        object::generate_signer_for_extending(&borrow_global<DaoSigner>(dao_addr).extend_ref)
    }

    // -----------------------------------
    // Unit Tests
    // -----------------------------------

    #[test_only]
    use aptos_framework::timestamp;
    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::aptos_coin::{Self};

    #[test_only]
    public fun setup_test(
        aptos_framework : &signer, 
        dao_generator : &signer,
        creator : &signer,
        fee_receiver: &signer,
        member_one : &signer,
        member_two : &signer,
        start_time : u64,
    ) : (address, address, address, address) acquires DaoSigner {

        init_module(dao_generator);

        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Set an initial time for testing
        timestamp::update_global_time_for_test(start_time);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);

        // dao signer
        let dao_signer_addr = get_dao_addr();
        let dao_signer      = get_dao_signer(dao_signer_addr);

        // get addresses
        let dao_addr            = signer::address_of(dao_generator);
        let fee_receiver_addr   = signer::address_of(fee_receiver);
        let creator_addr        = signer::address_of(creator);
        let member_one_addr     = signer::address_of(member_one);
        let member_two_addr     = signer::address_of(member_two);

        // create accounts
        account::create_account_for_test(dao_signer_addr);
        account::create_account_for_test(dao_addr);
        account::create_account_for_test(fee_receiver_addr);
        account::create_account_for_test(creator_addr);
        account::create_account_for_test(member_one_addr);
        account::create_account_for_test(member_two_addr);

        // register accounts
        coin::register<AptosCoin>(&dao_signer);
        coin::register<AptosCoin>(dao_generator);
        coin::register<AptosCoin>(fee_receiver);
        coin::register<AptosCoin>(creator);
        coin::register<AptosCoin>(member_one);
        coin::register<AptosCoin>(member_two);

        // mint some AptosCoin to the accounts
        let creator_coins      = coin::mint<AptosCoin>(100_000_000_000, &mint_cap);
        let member_one_coins   = coin::mint<AptosCoin>(100_000_000_000, &mint_cap);
        let member_two_coins   = coin::mint<AptosCoin>(100_000_000_000, &mint_cap);

        coin::deposit(creator_addr     , creator_coins);
        coin::deposit(member_one_addr  , member_one_coins);
        coin::deposit(member_two_addr  , member_two_coins);

        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        (dao_addr, creator_addr, member_one_addr, member_two_addr)
    }

    #[view]
    #[test_only]
    public fun test_NewProposalEvent(
        proposal_id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String, 
        description: String,
        duration: u64 
    ): NewProposalEvent {
        let event = NewProposalEvent{
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            duration
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_NewVoteEvent(
        proposal_id: u64,
        voter: address,
        vote_type: u8,
        vote_count: u64
    ): NewVoteEvent {
        let event = NewVoteEvent{
            proposal_id,
            voter,
            vote_type,
            vote_count
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_ProposalExecutedEvent(
        proposal_id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String, 
        description: String,
        result: String,
        executed: bool
    ): ProposalExecutedEvent {
        let event = ProposalExecutedEvent{
            proposal_id,
            proposal_type,
            proposal_sub_type,
            title,
            description,
            result,
            executed
        };
        return event
    }

}
