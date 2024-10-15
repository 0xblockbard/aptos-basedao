#[test_only]
module basedao_addr::hybrid_dao_test {

    use basedao_addr::hybrid_dao;
    use basedao_addr::gov_token;
    use basedao_addr::moon_coin;
    
    use std::signer;
    use std::option::{Self};
    use std::string::{Self, String};

    use aptos_std::smart_table::{SmartTable};
    
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::event::{was_event_emitted};
    use aptos_framework::fungible_asset::{Metadata, MintRef, TransferRef, BurnRef};

    // -----------------------------------
    // Errors
    // -----------------------------------

    const ERROR_NOT_ADMIN : u64                             = 1;
    const ERROR_DAO_IS_ALREADY_SETUP: u64                   = 2;
    const ERROR_DAO_IS_PAUSED: u64                          = 3;
    const ERROR_INVALID_PROPOSAL_SUB_TYPE: u64              = 4;
    const ERROR_INCORRECT_CREATION_FEE : u64                = 4;
    const ERROR_INSUFFICIENT_VOTE_WEIGHT : u64              = 5;
    const ERROR_PROPOSAL_EXPIRED : u64                      = 6;
    const ERROR_INVALID_TOKEN_METADATA: u64                 = 7;
    const ERROR_PROPOSAL_HAS_NOT_ENDED: u64                 = 8;
    const ERROR_INVALID_UPDATE_TYPE: u64                    = 9;
    const ERROR_MISSING_TRANSFER_RECIPIENT: u64             = 10;
    const ERROR_MISSING_TRANSFER_AMOUNT: u64                = 11;
    const ERROR_MISSING_TRANSFER_METADATA: u64              = 12;
    const ERROR_SHOULD_HAVE_AT_LEAST_ONE_PROPOSAL_TYPE: u64 = 13;
    const ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED: u64 = 14;
    const ERROR_MISMATCH_COIN_STRUCT_NAME: u64              = 15;
    const ERROR_NOT_GUILD_MEMBER: u64                       = 16;
    const ERROR_INSUFFICIENT_ROLE_PERMISSION: u64           = 17;
    const ERROR_INVALID_ROLE: u64                           = 18;

    // -----------------------------------
    // Constants
    // -----------------------------------

    const CREATION_FEE: u64                                 = 1;     
    const FEE_RECEIVER: address                             = @fee_receiver_addr;
    
    const DEFAULT_RECRUIT_VOTE_MULTIPLIER: u64              = 1;
    const DEFAULT_NOVICE_VOTE_MULTIPLIER: u64               = 2;
    const DEFAULT_EXECUTIVE_VOTE_MULTIPLIER: u64            = 8;
    const DEFAULT_LEADER_VOTE_MULTIPLIER: u64               = 9;

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
        vote_type: u8,   // 0 -> against, 1 -> for, 2 -> pass
        vote_count: u64
    }

    /// Proposal Struct
    struct Proposal has store {
        id: u64,
        proposal_type: String,
        proposal_sub_type: String,
        title: String,
        description: String,
        votes_for: u64,
        votes_pass: u64,
        votes_against: u64,
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
        opt_transfer_metadata: option::Option<Object<Metadata>>,

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
        next_proposal_id : u64,
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

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Global state to pause the FA coin.
    /// OPTIONAL
    struct State has key {
        paused: bool,
    }

    struct MoonCoin {}

    // -----------------------------------
    // Test Constants
    // -----------------------------------

    const TEST_START_TIME : u64 = 1000000000;

    // -----------------------------------
    // Unit Test Helpers
    // -----------------------------------

    public fun call_init_dao(
        creator: &signer,
        gov_token_metadata: Object<Metadata>
    ){

        // set up initial values for creating a campaign
        let name            = string::utf8(b"Test DAO Name");
        let description     = string::utf8(b"Test DAO Description");
        let image_url       = string::utf8(b"Test DAO Image Url");

        // call setup dao
        hybrid_dao::init_dao(
            creator,
            name,
            description,
            image_url,
            gov_token_metadata
        );

    }

    // -----------------------------------
    // Unit Tests
    // -----------------------------------

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_init_dao(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);

        // set up initial values for creating a campaign
        let name            = string::utf8(b"Test DAO Name");
        let description     = string::utf8(b"Test DAO Description");
        let image_url       = string::utf8(b"Test DAO Image Url");

        // get aptos coin balances before init_dao
        let creator_balance_before      = coin::balance<AptosCoin>(signer::address_of(creator));
        let fee_receiver_balance_before = coin::balance<AptosCoin>(signer::address_of(fee_receiver));

        // call setup dao
        hybrid_dao::init_dao(
            creator,
            name,
            description,
            image_url,
            gov_token_metadata
        );

        // get aptos coin balances after init_dao
        let creator_balance_after       = coin::balance<AptosCoin>(signer::address_of(creator));
        let fee_receiver_balance_after  = coin::balance<AptosCoin>(signer::address_of(fee_receiver));

        // get dao info view
        let (
            dao_creator,
            dao_name,
            dao_description,
            dao_image_url,
            dao_type,
            dao_governance_token_metadata,
            _min_executive_vote_weight,
            _min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();
        
        // verify dao details
        assert!(dao_creator == signer::address_of(creator)          , 100);
        assert!(dao_name == name                                    , 101);
        assert!(dao_description == description                      , 102);
        assert!(dao_image_url == image_url                          , 103);
        assert!(dao_type == string::utf8(b"guild")                  , 104);
        assert!(dao_governance_token_metadata == gov_token_metadata , 105);

        // verify creation fee was paid
        assert!(creator_balance_before >= creator_balance_after                          , 106);
        assert!(fee_receiver_balance_after >= fee_receiver_balance_before                , 107);
        assert!(creator_balance_before - creator_balance_after == CREATION_FEE           , 108);
        assert!(fee_receiver_balance_after - fee_receiver_balance_before == CREATION_FEE , 109);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure]
    public entry fun test_init_dao_cannot_be_called_more_than_once(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);

        // set up initial values for creating a campaign
        let name            = string::utf8(b"Test DAO Name");
        let description     = string::utf8(b"Test DAO Description");
        let image_url       = string::utf8(b"Test DAO Image Url");

        // call setup dao
        hybrid_dao::init_dao(
            creator,
            name,
            description,
            image_url,
            gov_token_metadata
        );

        // call setup dao
        hybrid_dao::init_dao(
            creator,
            name,
            description,
            image_url,
            gov_token_metadata
        );

    }


    // -----------------------------------
    // Leader Functions
    // -----------------------------------

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_leader_can_update_executive_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // this adjusts min_executive_vote_weight required to access executive entrypoints
        let new_min_executive_vote_weight = 600;
        hybrid_dao::update_executive_vote_weight(creator, new_min_executive_vote_weight);

        // get dao info
        let (
            _dao_creator,
            _dao_name,
            _dao_description,
            _dao_image_url,
            _dao_type,
            _dao_governance_token_metadata,
            min_executive_vote_weight,
            _min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();

        assert!(min_executive_vote_weight == new_min_executive_vote_weight, 100);
    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_update_executive_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // this adjusts min_executive_vote_weight required to access executive entrypoints
        let new_min_executive_vote_weight = 600;
        hybrid_dao::update_executive_vote_weight(member_one, new_min_executive_vote_weight);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_update_executive_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // this adjusts min_executive_vote_weight required to access executive entrypoints
        let new_min_executive_vote_weight = 600;
        hybrid_dao::update_executive_vote_weight(member_one, new_min_executive_vote_weight);

    }



    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_leader_can_update_leader_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // this adjusts min_leader_vote_weight required to access leader entrypoints
        let new_min_leader_vote_weight = 600;
        hybrid_dao::update_leader_vote_weight(creator, new_min_leader_vote_weight);

        // get dao info
        let (
            _dao_creator,
            _dao_name,
            _dao_description,
            _dao_image_url,
            _dao_type,
            _dao_governance_token_metadata,
            _min_executive_vote_weight,
            min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();

        assert!(min_leader_vote_weight == new_min_leader_vote_weight, 100);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_update_leader_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // this adjusts min_leader_vote_weight required to access leader entrypoints
        let new_min_leader_vote_weight = 600;
        hybrid_dao::update_leader_vote_weight(member_one, new_min_leader_vote_weight);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_update_leader_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // this adjusts min_leader_vote_weight required to access leader entrypoints
        let new_min_leader_vote_weight = 600;
        hybrid_dao::update_leader_vote_weight(member_one, new_min_leader_vote_weight);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_leader_can_add_or_update_or_remove_proposal_types(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add new proposal type
        let proposal_type_name              = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = 5;
        let min_amount_to_create_proposal   = 10;
        let min_amount_to_execute_proposal  = 20;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type_name,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        // get new proposal type info
        let ( 
            view_duration, 
            view_min_amount_to_vote, 
            view_min_amount_to_create_proposal, 
            view_min_amount_to_execute_proposal
        )   = hybrid_dao::get_proposal_type_info(proposal_type_name);

        assert!(view_duration                        == duration                        , 101);
        assert!(view_min_amount_to_vote              == min_amount_to_vote              , 102);
        assert!(view_min_amount_to_create_proposal   == min_amount_to_create_proposal   , 103);
        assert!(view_min_amount_to_execute_proposal  == min_amount_to_execute_proposal  , 104);

        // update proposal type 
        duration                        = 20000;
        min_amount_to_vote              = 11;
        min_amount_to_create_proposal   = 21;
        min_amount_to_execute_proposal  = 31;

        // update proposal type
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type_name,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        // get updated proposal type info
        let ( 
            view_duration, 
            view_min_amount_to_vote, 
            view_min_amount_to_create_proposal, 
            view_min_amount_to_execute_proposal
        )   = hybrid_dao::get_proposal_type_info(proposal_type_name);

        assert!(view_duration                        == duration                        , 101);
        assert!(view_min_amount_to_vote              == min_amount_to_vote              , 102);
        assert!(view_min_amount_to_create_proposal   == min_amount_to_create_proposal   , 103);
        assert!(view_min_amount_to_execute_proposal  == min_amount_to_execute_proposal  , 104);

        // remove proposal
        hybrid_dao::remove_proposal_types(
            creator,
            proposal_type_name
        );
    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_add_or_update_proposal_types(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add new proposal type
        let proposal_type_name              = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = 5;
        let min_amount_to_create_proposal   = 10;
        let min_amount_to_execute_proposal  = 20;

        // add new proposal should fail
        hybrid_dao::add_or_update_proposal_types(
            member_one,
            proposal_type_name,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_add_or_update_proposal_types(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type_name              = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = 5;
        let min_amount_to_create_proposal   = 10;
        let min_amount_to_execute_proposal  = 20;

        // add new proposal should fail
        hybrid_dao::add_or_update_proposal_types(
            member_one,
            proposal_type_name,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_remove_proposal_types(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // proposal type
        let proposal_type_name = string::utf8(b"standard");

        // remove proposal // should fail
        hybrid_dao::remove_proposal_types(
            member_one,
            proposal_type_name
        );

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_remove_proposal_types(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // proposal type
        let proposal_type_name = string::utf8(b"standard");

        // remove proposal should fail
        hybrid_dao::remove_proposal_types(
            member_one,
            proposal_type_name
        );

    }

    // -----------------------------------
    // Executive Functions
    // -----------------------------------

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_executive_can_add_or_update_or_remove_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        let role_to_add  = string::utf8(b"NEW ROLE");
        let vote_weight  = 1;

        // add new role with vote weight below executive (7)
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

        // edit role with vote weight below executive (7)
        vote_weight  = 5; 
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

        // remove role
        hybrid_dao::remove_role(member_one, role_to_add);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_add_or_update_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let role_to_add  = string::utf8(b"novice");
        let vote_weight  = 150;

        // should fail
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_add_or_update_row(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        let role_to_add  = string::utf8(b"novice");
        let vote_weight  = 1;

        // should fail
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

    }



    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_edit_his_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        let role_to_edit = string::utf8(b"leader");
        let vote_weight  = 150;

        // should fail as role has greater weight than current executive role (800)
        hybrid_dao::add_or_update_role(member_one, role_to_edit, vote_weight);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_remove_roles_equal_or_above_his(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // should fail
        hybrid_dao::remove_role(member_one, new_member_role);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_add_a_new_role_with_weight_greater_than_his_own(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        let role_to_add  = string::utf8(b"superfounder");
        let vote_weight  = 20;

        // should fail as new vote weight is greater than current executive role (8)
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_update_a_role_with_weight_greater_than_his_own(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        let role_to_add  = string::utf8(b"leader");
        let vote_weight  = 5;

        // should fail as executive should not be able to edit leader role
        hybrid_dao::add_or_update_role(member_one, role_to_add, vote_weight);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_remove_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let role_to_add  = string::utf8(b"recruit");

        // should fail
        hybrid_dao::remove_role(member_one, role_to_add);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_remove_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild as recruit
        let new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);


        let role_to_add  = string::utf8(b"recruit");

        // should fail
        hybrid_dao::remove_role(member_one, role_to_add);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_guild_member_cannot_add_or_update_member(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // should fail: add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_one), new_member_role);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_add_member(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild as recruit
        let new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // should fail: add/update member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_one), new_member_role);

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INVALID_ROLE, location = hybrid_dao)]
    public entry fun test_executive_cannot_add_or_update_member_with_invalid_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // should fail
        new_member_role = string::utf8(b"wrongrole");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_two), new_member_role);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_add_or_update_member_with_equal_or_higher_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // should fail - executive cannot add others as executives
        new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_two), new_member_role);

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_executive_can_remove_members_with_lower_roles_than_his(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // add new recruit
        new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_two), new_member_role);

        // remove new recruit
        hybrid_dao::remove_member(member_one, signer::address_of(member_two));

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_member_with_low_role_cannot_remove_member(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild as executive
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // add new recruit
        new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(member_one, signer::address_of(member_two), new_member_role);

        // should fail: remove member
        hybrid_dao::remove_member(member_two, signer::address_of(member_one));

    }

    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_NOT_GUILD_MEMBER, location = hybrid_dao)]
    public entry fun test_non_member_cannot_remove_guild_member(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // should fail: remove member
        hybrid_dao::remove_member(member_one, signer::address_of(creator));

    }


    #[test(aptos_framework = @0x1, dao_generator=@basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_ROLE_PERMISSION, location = hybrid_dao)]
    public entry fun test_executive_cannot_remove_guild_member_with_higher_role(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_two), new_member_role);

        // should fail - executive cannot remove higher roles
        hybrid_dao::remove_member(member_one, signer::address_of(creator));

    }



    // -----------------------------------
    // Proposals
    // -----------------------------------

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_create_standard_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let proposal_title       = string::utf8(b"Test Proposal Name");
        let proposal_description = string::utf8(b"Test Proposal Description");
        let proposal_type        = string::utf8(b"standard");

        // should fail
        hybrid_dao::create_standard_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_create_fa_transfer_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;

        // should fail
        hybrid_dao::create_fa_transfer_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_create_coin_transfer_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoin";

        // should fail
        hybrid_dao::create_coin_transfer_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_create_proposal_update_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);

        // should fail
        hybrid_dao::create_proposal_update_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_create_dao_update_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::some(string::utf8(b"New DAO Description"));
        let opt_dao_image_url       = option::some(string::utf8(b"New DAO Image URL"));

        // should fail
        hybrid_dao::create_dao_update_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_sufficient_governance_tokens_can_create_standard_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  { 

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        let ( duration, _, _, _)   = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        // check event emits expected info
        let proposal_sub_type  = string::utf8(b"standard");
        let new_proposal_event = hybrid_dao::test_NewProposalEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            duration
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_proposal_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_sufficient_governance_tokens_can_create_fa_transfer_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // add member to guild
        let new_member_role = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // mint gov tokens to member_one
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_two);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // check that ProposalTable does not exist
        assert!(!exists<ProposalTable>(signer::address_of(member_one)), 98);

        // should pass
        hybrid_dao::create_fa_transfer_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        // check event emits expected info
        let proposal_sub_type  = string::utf8(b"fa_transfer");
        let new_proposal_event = hybrid_dao::test_NewProposalEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            duration
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_proposal_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_sufficient_governance_tokens_can_create_proposal_update_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();
        
        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id                         = hybrid_dao::get_next_proposal_id();
        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);
        let ( duration, _, _, _)                = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        // check event emits expected info
        let proposal_sub_type  = string::utf8(b"proposal_update");
        let new_proposal_event = hybrid_dao::test_NewProposalEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            duration
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_proposal_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INVALID_UPDATE_TYPE, location = hybrid_dao)]
    public entry fun test_user_cannot_create_proposal_update_proposal_with_invalid_update_type(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"asdasd"); // invalid update type
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);

        // should fail
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_guild_member_can_create_dao_update_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {  

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::some(string::utf8(b"New DAO Description"));
        let opt_dao_image_url       = option::some(string::utf8(b"New DAO Image URL"));
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_dao_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

        // check event emits expected info
        let proposal_sub_type  = string::utf8(b"dao_update");
        let new_proposal_event = hybrid_dao::test_NewProposalEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            duration
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_proposal_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_sufficient_vote_weight_can_vote_yay_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        let proposal_sub_type      = string::utf8(b"standard");
        
        let ( duration, _, _, min_amount_to_execute_proposal)    = hybrid_dao::get_proposal_type_info(proposal_type);

        let start_timestamp = timestamp::now_seconds();
        let end_timestamp   = timestamp::now_seconds() + duration;

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // calculate final vote weight
        let final_vote_weight = mint_amount * DEFAULT_LEADER_VOTE_MULTIPLIER;

        // check event emits expected info
        let new_vote_event = hybrid_dao::test_NewVoteEvent(
            proposal_id,
            signer::address_of(creator),
            vote_type,
            final_vote_weight
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_vote_event), 100);

        // verify that votes was added propoerly
        let (
            view_proposal_type,
            view_proposal_sub_type,
            view_title,
            view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            view_min_amount_to_execute_proposal,

            view_duration,
            view_start_timestamp,
            view_end_timestamp,
            
            view_result,
            view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_proposal_type                  == proposal_type                    , 101);
        assert!(view_proposal_sub_type              == proposal_sub_type                , 102);
        assert!(view_title                          == proposal_title                   , 103);
        assert!(view_description                    == proposal_description             , 104);
        assert!(view_votes_yay                      == final_vote_weight                , 105);
        assert!(view_votes_pass                     == 0                                , 106);
        assert!(view_votes_nay                      == 0                                , 107);
        assert!(view_total_votes                    == final_vote_weight                , 109);
        assert!(view_min_amount_to_execute_proposal == min_amount_to_execute_proposal   , 109);
        assert!(view_duration                       == duration                         , 110);
        assert!(view_start_timestamp                == start_timestamp                  , 111);
        assert!(view_end_timestamp                  == end_timestamp                    , 112);
        assert!(view_result                         == string::utf8(b"PENDING")         , 113);
        assert!(view_executed                       == false                            , 114);

        // get user vote info view
        let (
            view_vote_type,
            view_vote_count 
        ) = hybrid_dao::get_proposal_voter_info(proposal_id, signer::address_of(creator));

        assert!(view_vote_type == vote_type                     , 115);
        assert!(view_vote_count == final_vote_weight            , 116);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_guild_member_can_vote_nay_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        
        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 0; // vote NAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // calculate final vote weight
        let final_vote_weight = mint_amount * DEFAULT_LEADER_VOTE_MULTIPLIER;

        // check event emits expected info
        let new_vote_event = hybrid_dao::test_NewVoteEvent(
            proposal_id,
            signer::address_of(creator),
            vote_type,
            final_vote_weight
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_vote_event), 100);

        // verify that votes was added propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_min_amount_to_execute_proposal,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay              == 0                            , 101);
        assert!(view_votes_pass             == 0                            , 102);
        assert!(view_votes_nay              == final_vote_weight            , 103);
        assert!(view_total_votes            == final_vote_weight            , 104);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_guild_member_can_vote_pass_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 2; // vote PASS
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // calculate final vote weight
        let final_vote_weight = mint_amount * DEFAULT_LEADER_VOTE_MULTIPLIER;

        // check event emits expected info
        let new_vote_event = hybrid_dao::test_NewVoteEvent(
            proposal_id,
            signer::address_of(creator),
            vote_type,
            final_vote_weight
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&new_vote_event), 100);

        // verify that votes was added propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_min_amount_to_execute_proposal,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay              == 0                            , 101);
        assert!(view_votes_pass             == final_vote_weight            , 102);
        assert!(view_votes_nay              == 0                            , 103);
        assert!(view_total_votes            == final_vote_weight            , 104);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_multiple_guild_members_can_vote_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();
        
        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_two), mint_amount);

        // add members to guild
        let default_new_member_role = string::utf8(b"novice");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_two), default_new_member_role);

        // calculate final vote weights
        let novice_final_vote_weight = mint_amount * DEFAULT_NOVICE_VOTE_MULTIPLIER;
        let leader_final_vote_weight = mint_amount * DEFAULT_LEADER_VOTE_MULTIPLIER;

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        
        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 0; // vote NAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        vote_type = 2; // vote PASS
        hybrid_dao::vote_for_proposal(
            member_two,
            proposal_id,
            vote_type
        );
        
        // verify that votes was added propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_min_amount_to_execute_proposal,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay     == novice_final_vote_weight                                      , 101);
        assert!(view_votes_pass    == novice_final_vote_weight                                      , 102);
        assert!(view_votes_nay     == leader_final_vote_weight                                      , 103);
        assert!(view_total_votes   == leader_final_vote_weight + (novice_final_vote_weight * 2)     , 104);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_user_can_change_vote_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator and member one
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add members to guild
        let default_new_member_role     = string::utf8(b"novice");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        // calculate final vote weight
        let final_vote_weight = mint_amount * DEFAULT_NOVICE_VOTE_MULTIPLIER;

        // verify that votes was added propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_success_vote_percent,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay              == final_vote_weight    , 101);
        assert!(view_votes_pass             == 0                    , 102);
        assert!(view_votes_nay              == 0                    , 103);
        assert!(view_total_votes            == final_vote_weight    , 104);

        vote_type = 0; // change vote to NAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        // verify that votes was changed propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_success_vote_percent,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay              == 0                     , 105);
        assert!(view_votes_pass             == 0                     , 106);
        assert!(view_votes_nay              == final_vote_weight     , 107);
        assert!(view_total_votes            == final_vote_weight     , 108);

        // test with member role change from recruit to executive
        let new_member_role         = string::utf8(b"executive");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), new_member_role);

        // calculate new final vote weight
        let new_final_vote_weight = mint_amount * DEFAULT_EXECUTIVE_VOTE_MULTIPLIER;

        vote_type = 2; // change vote to PASS
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        // verify that votes was changed propoerly
        let (
            _view_proposal_type,
            _view_proposal_sub_type,
            _view_title,
            _view_description,

            view_votes_yay,
            view_votes_pass,
            view_votes_nay,
            view_total_votes,
            _view_success_vote_percent,

            _view_duration,
            _view_start_timestamp,
            _view_end_timestamp,
            
            _view_result,
            _view_executed
        ) = hybrid_dao::get_proposal_info(proposal_id);

        assert!(view_votes_yay              == 0                        , 109);
        assert!(view_votes_pass             == new_final_vote_weight    , 110);
        assert!(view_votes_nay              == 0                        , 111);
        assert!(view_total_votes            == new_final_vote_weight    , 112);

        vote_type = 2; // no change to vote 
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        vote_type = 1; // change vote to YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_PROPOSAL_EXPIRED, location = hybrid_dao)]
    public entry fun test_user_cannot_vote_for_expired_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        let ( duration, _, _, _)   = hybrid_dao::get_proposal_type_info(proposal_type);

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        // fast forward to proposal duration over
        timestamp::fast_forward_seconds(duration + 1);

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_vote_for_proposal(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_insufficient_vote_weight_cannot_vote_for_proposal_with_higher_min_amount_to_vote_than_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to member and creator
        let mint_amount = 20_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount;
        let min_amount_to_execute_proposal  = mint_amount;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        // should fail as member one is recruit (20_000_000 * 1) but proposal type requires at least (20_000_000 * 3)
        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_standard_proposal_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        let proposal_sub_type      = string::utf8(b"standard");
        let ( duration, _, _, _)   = hybrid_dao::get_proposal_type_info(proposal_type);

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // check event emits expected info
        let proposal_executed_event = hybrid_dao::test_ProposalExecutedEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            string::utf8(b"SUCCESS"), // proposal result
            true                           // proposal executed
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&proposal_executed_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_PROPOSAL_HAS_NOT_ENDED, location = hybrid_dao)]
    public entry fun test_proposal_cannot_be_executed_if_duration_has_not_ended(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // should fail
        hybrid_dao::execute_proposal(
            proposal_id
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_standard_proposal_can_be_executed_but_with_fail_result_with_insufficient_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator and member
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add members to guild
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        let proposal_id            = hybrid_dao::get_next_proposal_id();
        let proposal_title         = string::utf8(b"Test Proposal Name");
        let proposal_description   = string::utf8(b"Test Proposal Description");
        let proposal_type          = string::utf8(b"standard");
        let proposal_sub_type      = string::utf8(b"standard");
        let ( duration, _, _, _)   = hybrid_dao::get_proposal_type_info(proposal_type);

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            member_one,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // check event emits expected info
        let proposal_executed_event = hybrid_dao::test_ProposalExecutedEvent(
            proposal_id,
            proposal_type,
            proposal_sub_type,
            proposal_title,
            proposal_description,
            string::utf8(b"FAIL"), // proposal result
            true                   // proposal executed
        );

        // verify if expected event was emitted
        assert!(was_event_emitted(&proposal_executed_event), 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_add_new_proposal_type_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id                         = hybrid_dao::get_next_proposal_id();
        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);
        let ( duration, _, _, _)                = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get new proposal type info
        let ( 
            new_duration, 
            new_success_vote_percent, 
            new_min_amount_to_vote, 
            new_min_amount_to_create_proposal
        )   = hybrid_dao::get_proposal_type_info(opt_proposal_type);

        assert!(new_duration                        == option::destroy_some(opt_duration)                       , 100);
        assert!(new_success_vote_percent            == option::destroy_some(opt_success_vote_percent)           , 101);
        assert!(new_min_amount_to_vote              == option::destroy_some(opt_min_amount_to_vote)             , 102);
        assert!(new_min_amount_to_create_proposal   == option::destroy_some(opt_min_amount_to_create_proposal)  , 103);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_update_proposal_type_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id                         = hybrid_dao::get_next_proposal_id();
        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"standard");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);
        let ( duration, _, _, _)                = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get updated proposal type info
        let ( 
            new_duration, 
            new_success_vote_percent, 
            new_min_amount_to_vote, 
            new_min_amount_to_create_proposal
        )   = hybrid_dao::get_proposal_type_info(opt_proposal_type);

        assert!(new_duration                        == option::destroy_some(opt_duration)                       , 100);
        assert!(new_success_vote_percent            == option::destroy_some(opt_success_vote_percent)           , 101);
        assert!(new_min_amount_to_vote              == option::destroy_some(opt_min_amount_to_vote)             , 102);
        assert!(new_min_amount_to_create_proposal   == option::destroy_some(opt_min_amount_to_create_proposal)  , 103);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_SHOULD_HAVE_AT_LEAST_ONE_PROPOSAL_TYPE, location = hybrid_dao)]
    public entry fun test_proposal_execution_fails_to_remove_proposal_type_if_there_are_none_left(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id                         = hybrid_dao::get_next_proposal_id();
        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"standard");
        let opt_update_type                     = string::utf8(b"remove");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);
        let ( duration, _, _, _)                = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure]
    public entry fun test_proposal_to_remove_proposal_type_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {   

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id                         = hybrid_dao::get_next_proposal_id();
        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let proposal_type                       = string::utf8(b"standard");
        let opt_proposal_type                   = string::utf8(b"advanced");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);
        let ( duration, _, _, _)                = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // add a new ADVANCED proposal type!
        hybrid_dao::execute_proposal(
            proposal_id
        );

        // start new proposal to remove ADVANCED proposal type
        proposal_id                         = hybrid_dao::get_next_proposal_id();
        proposal_title                      = string::utf8(b"Test Proposal Name");
        proposal_description                = string::utf8(b"Test Proposal Description");
        proposal_type                       = string::utf8(b"standard");
        opt_proposal_type                   = string::utf8(b"advanced");
        opt_update_type                     = string::utf8(b"remove");
        opt_duration                        = option::none();
        opt_success_vote_percent            = option::none();
        opt_min_amount_to_vote              = option::none();
        opt_min_amount_to_create_proposal   = option::none();

        // should pass
        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // remove ADVANCED proposal type
        hybrid_dao::execute_proposal(
            proposal_id
        );

        // should fail as proposal type has now been removed
        let ( _, _, _, _)   = hybrid_dao::get_proposal_type_info(opt_proposal_type);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_update_dao_info_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::some(string::utf8(b"New DAO Description"));
        let opt_dao_image_url       = option::some(string::utf8(b"New DAO Image URL"));
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_dao_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get new dao info
        let (
            _dao_creator,
            dao_name,
            dao_description,
            dao_image_url,
            _dao_type,
            _dao_governance_token_metadata,
            _min_executive_vote_weight,
            _min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();

        assert!(dao_name        == option::destroy_some(opt_dao_name)         , 100);
        assert!(dao_description == option::destroy_some(opt_dao_description)  , 101);
        assert!(dao_image_url   == option::destroy_some(opt_dao_image_url)    , 102);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_update_partial_dao_info_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::none();
        let opt_dao_image_url       = option::none();
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_dao_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // get initial dao type info
        let (
            _dao_creator,
            _initial_dao_name,
            initial_dao_description,
            initial_dao_image_url,
            _dao_type,
            _dao_governance_token_metadata,
            _min_executive_vote_weight,
            _min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get new dao info
        let (
            _dao_creator,
            dao_name,
            dao_description,
            dao_image_url,
            _dao_type,
            _dao_governance_token_metadata,
            _min_executive_vote_weight,
            _min_leader_vote_weight,
            _role_count,
            _member_count
        ) = hybrid_dao::get_dao_info();

        assert!(dao_name        == option::destroy_some(opt_dao_name)   , 100);
        assert!(dao_description == initial_dao_description              , 101);
        assert!(dao_image_url   == initial_dao_image_url                , 102);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_transfer_fungible_assets_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 100_000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // deposit some gov tokens to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_fa_to_dao(
            creator,
            deposit_amount,
            gov_token_metadata
        );

        // should pass
        hybrid_dao::create_fa_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // get member one balance before proposal execution
        let member_gov_token_balance_before = primary_fungible_store::balance(signer::address_of(member_one), gov_token_metadata);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get member one balance after proposal execution
        let member_gov_token_balance_after = primary_fungible_store::balance(signer::address_of(member_one), gov_token_metadata);

        // verify gov token transferred to member one
        assert!(member_gov_token_balance_after == member_gov_token_balance_before + opt_transfer_amount, 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure]
    public entry fun test_proposal_to_transfer_fungible_assets_should_fail_if_dao_does_not_have_sufficient_tokens_to_transfer(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

         // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 100_000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_fa_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // get member one balance before proposal execution
        let member_gov_token_balance_before = primary_fungible_store::balance(signer::address_of(member_one), gov_token_metadata);

        hybrid_dao::execute_proposal(
            proposal_id
        );

        // get member one balance after proposal execution
        let member_gov_token_balance_after = primary_fungible_store::balance(signer::address_of(member_one), gov_token_metadata);

        // verify gov token transferred to member one
        assert!(member_gov_token_balance_after == member_gov_token_balance_before + opt_transfer_amount, 100);

    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED, location = hybrid_dao)]
    public entry fun test_proposal_to_transfer_fungible_assets_should_fail_if_called_by_wrong_execute_proposal_function(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

     // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 100_000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // should pass
        hybrid_dao::create_fa_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        hybrid_dao::execute_coin_transfer_proposal<AptosCoin>(
            proposal_id
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_transfer_coins_can_be_executed_successfully_with_enough_yay_votes(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 100_000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoin";
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // deposit some coins to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<AptosCoin>(
            creator,
            deposit_amount
        );

        // should pass
        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // get member one balance before proposal execution
        let member_coin_balance_before = coin::balance<AptosCoin>(signer::address_of(member_one));

        // should pass
        hybrid_dao::execute_coin_transfer_proposal<AptosCoin>(
            proposal_id
        );

        // get member one balance after proposal execution
        let member_coin_balance_after = coin::balance<AptosCoin>(signer::address_of(member_one));

        // verify gov token transferred to member one
        assert!(member_coin_balance_after == member_coin_balance_before + opt_transfer_amount, 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_coin_store_created_on_new_coin_deposit(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint moon coins to member
        moon_coin::initialize<MoonCoin>(
            dao_generator,
            b"Moon Coin",
            b"MOON",
            8,
            true
        );
        let mint_amount = 100_000_000_000;
        moon_coin::register<MoonCoin>(member_one);
        moon_coin::mint<MoonCoin>(dao_generator, signer::address_of(member_one), mint_amount);
        
        // deposit some coins to dao
        let deposit_amount = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<MoonCoin>(
            member_one,
            deposit_amount
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_proposal_to_transfer_coins_with_insufficient_yay_votes_will_have_fail_result(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoin";
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // deposit some coins to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<AptosCoin>(
            creator,
            deposit_amount
        );

        // should pass
        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // get member one balance before proposal execution
        let member_coin_balance_before = coin::balance<AptosCoin>(signer::address_of(member_one));

        // should pass
        hybrid_dao::execute_coin_transfer_proposal<AptosCoin>(
            proposal_id
        );

        // get member one balance after proposal execution
        let member_coin_balance_after = coin::balance<AptosCoin>(signer::address_of(member_one));

        // verify gov token transferred to member one
        assert!(member_coin_balance_after == member_coin_balance_before, 100);
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_WRONG_EXECUTE_PROPOSAL_FUNCTION_CALLED, location = hybrid_dao)]
    public entry fun test_proposal_to_transfer_coins_should_fail_if_called_by_wrong_execute_proposal_function(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoin";
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // deposit some coins to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<AptosCoin>(
            creator,
            deposit_amount
        );

        // should pass
        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // should fail
        hybrid_dao::execute_proposal(
            proposal_id
        );
    }

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_MISMATCH_COIN_STRUCT_NAME, location = hybrid_dao)]
    public entry fun test_proposal_to_transfer_coins_should_fail_if_given_wrong_coin_struct_name(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoinWrong";
        let ( duration, _, _, _)    = hybrid_dao::get_proposal_type_info(proposal_type);

        // deposit some coins to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<AptosCoin>(
            creator,
            deposit_amount
        );

        // should pass
        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // fast forward to end of propoasl
        timestamp::fast_forward_seconds(duration + 1);

        // should fail
        hybrid_dao::execute_coin_transfer_proposal<AptosCoin>(
            proposal_id
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_PROPOSAL_HAS_NOT_ENDED, location = hybrid_dao)]
    public entry fun test_execute_coin_transfer_proposal_should_fail_if_proposal_voting_has_not_ended(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_id             = hybrid_dao::get_next_proposal_id();
        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoinWrong";

        // deposit some coins to dao
        let deposit_amount          = 300_000_000;
        hybrid_dao::deposit_coin_to_dao<AptosCoin>(
            creator,
            deposit_amount
        );

        // should pass
        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        let vote_type = 1; // vote YAY
        hybrid_dao::vote_for_proposal(
            creator,
            proposal_id,
            vote_type
        );

        // should fail
        hybrid_dao::execute_coin_transfer_proposal<AptosCoin>(
            proposal_id
        );
    }


    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    public entry fun test_multiple_proposals_of_the_same_type_can_be_created(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {
        
        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 1000_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let proposal_type           = string::utf8(b"standard");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;

        // FA Transfer Proposal

        hybrid_dao::create_fa_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,          
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        hybrid_dao::create_fa_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,          
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

        // Coin Transfer Proposal

        let opt_coin_struct_name    = b"AptosCoin";

        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        hybrid_dao::create_coin_transfer_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

        // Proposal Update Proposal

        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);

        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        hybrid_dao::create_proposal_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

        // DAO update proposal

        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::some(string::utf8(b"New DAO Description"));
        let opt_dao_image_url       = option::some(string::utf8(b"New DAO Image URL"));

        hybrid_dao::create_dao_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

        hybrid_dao::create_dao_update_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

        // Standard Proposal

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

        hybrid_dao::create_standard_proposal(
            creator,
            proposal_title,
            proposal_description,
            proposal_type
        );

    }
    

    // // ---------------------------------------------
    // // Insufficient Role Permissions checks 
    // // ---------------------------------------------

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_guild_member_cannot_create_fa_transfer_proposal_if_vote_weight_required_exceeds_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {
        
        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount * 3; // set higher
        let min_amount_to_execute_proposal  = mint_amount * 3;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_transfer_metadata   = gov_token_metadata;

        // should fail as member one is recruit (mint_amount * 1) but proposal type requires at least (mint_amount * 3) vote weight
        hybrid_dao::create_fa_transfer_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,             
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_transfer_metadata
        );

    }

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_guild_member_cannot_create_coin_transfer_proposal_if_vote_weight_required_exceeds_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount * 3; // set higher
        let min_amount_to_execute_proposal  = mint_amount * 3;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let opt_transfer_recipient  = signer::address_of(member_one);
        let opt_transfer_amount     = 100_000_000;
        let opt_coin_struct_name    = b"AptosCoin";

        // should fail as member one is recruit (mint_amount * 1) but proposal type requires at least (mint_amount * 3) vote weight
        hybrid_dao::create_coin_transfer_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_transfer_recipient,
            opt_transfer_amount,
            opt_coin_struct_name
        );

    }

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_guild_member_cannot_create_proposal_update_proposal_if_vote_weight_required_exceeds_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount * 3; // set higher
        let min_amount_to_execute_proposal  = mint_amount * 3;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_title                      = string::utf8(b"Test Proposal Name");
        let proposal_description                = string::utf8(b"Test Proposal Description");
        let opt_proposal_type                   = string::utf8(b"new proposal type");
        let opt_update_type                     = string::utf8(b"update");
        let opt_duration                        = option::some(100_000_000);
        let opt_success_vote_percent            = option::some(2000);
        let opt_min_amount_to_vote              = option::some(100_000_000);
        let opt_min_amount_to_create_proposal   = option::some(100_000_000);

        // should fail as member one is recruit (mint_amount * 1) but proposal type requires at least (mint_amount * 3) vote weight
        hybrid_dao::create_proposal_update_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_proposal_type,
            opt_update_type,
            opt_duration,
            opt_success_vote_percent,
            opt_min_amount_to_vote,
            opt_min_amount_to_create_proposal
        );

    }

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_guild_member_cannot_create_dao_update_proposal_if_vote_weight_required_exceeds_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount * 3; // set higher
        let min_amount_to_execute_proposal  = mint_amount * 3;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");
        let opt_dao_name            = option::some(string::utf8(b"New DAO Name"));
        let opt_dao_description     = option::some(string::utf8(b"New DAO Description"));
        let opt_dao_image_url       = option::some(string::utf8(b"New DAO Image URL"));

        // should fail as member one is recruit (mint_amount * 1) but proposal type requires at least (mint_amount * 3) vote weight
        hybrid_dao::create_dao_update_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type,
            opt_dao_name,
            opt_dao_description,
            opt_dao_image_url
        );

    }

    #[test(aptos_framework = @0x1, dao_generator = @basedao_addr, creator = @0x123, fee_receiver = @fee_receiver_addr, member_one = @0x333, member_two = @0x444)]
    #[expected_failure(abort_code = ERROR_INSUFFICIENT_VOTE_WEIGHT, location = hybrid_dao)]
    public entry fun test_guild_member_cannot_create_standard_proposal_if_vote_weight_required_exceeds_his_final_vote_weight(
        aptos_framework: &signer,
        dao_generator: &signer,
        creator: &signer,
        fee_receiver: &signer,
        member_one: &signer,
        member_two: &signer,
    )  {

        // setup governance token and get metadata
        gov_token::setup_test(dao_generator);
        let gov_token_metadata = gov_token::metadata();

        // setup dao
        hybrid_dao::setup_test(aptos_framework, dao_generator, creator, fee_receiver, member_one, member_two, TEST_START_TIME);
        call_init_dao(creator, gov_token_metadata);

        // mint gov tokens to creator
        let mint_amount = 30_000_000;
        gov_token::mint(dao_generator, signer::address_of(creator), mint_amount);
        gov_token::mint(dao_generator, signer::address_of(member_one), mint_amount);

        // add member to guild as recruit
        let default_new_member_role = string::utf8(b"recruit");
        hybrid_dao::add_or_update_member(creator, signer::address_of(member_one), default_new_member_role);

        // add new proposal type
        let proposal_type                   = string::utf8(b"NEW_PROPOSAL_TYPE");
        let duration                        = 10000;
        let min_amount_to_vote              = mint_amount * 3; // set higher
        let min_amount_to_create_proposal   = mint_amount * 3; // set higher
        let min_amount_to_execute_proposal  = mint_amount * 3;

        // add new proposal
        hybrid_dao::add_or_update_proposal_types(
            creator,
            proposal_type,
            duration,
            min_amount_to_vote,
            min_amount_to_create_proposal,
            min_amount_to_execute_proposal
        );

        let proposal_title          = string::utf8(b"Test Proposal Name");
        let proposal_description    = string::utf8(b"Test Proposal Description");

        // should fail as member one is recruit (mint_amount * 1) but proposal type requires at least (mint_amount * 3) vote weight
        hybrid_dao::create_standard_proposal(
            member_one,
            proposal_title,
            proposal_description,
            proposal_type
        );

    }


}