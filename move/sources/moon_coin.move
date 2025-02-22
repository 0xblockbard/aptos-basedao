// basic coin module for testing purposes
module basedao_addr::moon_coin {

    struct MoonCoin {}

    use std::error;
    use std::signer;
    use std::string;

    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    //
    // Errors
    //

    /// Account has no capabilities (burn/mint).
    const ENO_CAPABILITIES: u64 = 1;

    //
    // Data structures
    //

    /// Capabilities resource storing mint and burn capabilities.
    /// The resource is stored on the account that initialized coin `CoinType`.
    struct Capabilities<phantom CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
    }

    //
    // Public functions
    //

    /// Withdraw an `amount` of coin `CoinType` from `account` and burn it.
    public entry fun burn<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires Capabilities {
        let account_addr = signer::address_of(account);

        assert!(
            exists<Capabilities<CoinType>>(account_addr),
            error::not_found(ENO_CAPABILITIES),
        );

        let capabilities = borrow_global<Capabilities<CoinType>>(account_addr);

        let to_burn = coin::withdraw<CoinType>(account, amount);
        coin::burn(to_burn, &capabilities.burn_cap);
    }

    /// Initialize new coin `CoinType` in Aptos Blockchain.
    /// Mint and Burn Capabilities will be stored under `account` in `Capabilities` resource.
    public entry fun initialize<CoinType>(
        account: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        monitor_supply: bool,
    ) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            account,
            string::utf8(name),
            string::utf8(symbol),
            decimals,
            monitor_supply,
        );

        move_to(account, Capabilities<CoinType> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    /// Create new coins `CoinType` and deposit them into dst_addr's account.
    public entry fun mint<CoinType>(
        account: &signer,
        dst_addr: address,
        amount: u64,
    ) acquires Capabilities {
        let account_addr = signer::address_of(account);

        assert!(
            exists<Capabilities<CoinType>>(account_addr),
            error::not_found(ENO_CAPABILITIES),
        );

        let capabilities = borrow_global<Capabilities<CoinType>>(account_addr);
        let coins_minted = coin::mint(amount, &capabilities.mint_cap);
        coin::deposit(dst_addr, coins_minted);
    }

    /// Creating a resource that stores balance of `CoinType` on user's account, withdraw and deposit event handlers.
    /// Required if user wants to start accepting deposits of `CoinType` in his account.
    public entry fun register<CoinType>(account: &signer) {
        coin::register<CoinType>(account);
    }

    //
    // Tests
    //

    #[test_only]
    use std::option;

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @basedao_addr)]
    public entry fun test_end_to_end(
        source: signer,
        destination: signer,
        mod_account: signer
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);
        aptos_framework::account::create_account_for_test(source_addr);
        aptos_framework::account::create_account_for_test(destination_addr);
        aptos_framework::account::create_account_for_test(signer::address_of(&mod_account));

        initialize<MoonCoin>(
            &mod_account,
            b"Moon Coin",
            b"MOON",
            10,
            true
        );
        assert!(coin::is_coin_initialized<MoonCoin>(), 0);

        coin::register<MoonCoin>(&mod_account);
        register<MoonCoin>(&source);
        register<MoonCoin>(&destination);

        mint<MoonCoin>(&mod_account, source_addr, 50);
        mint<MoonCoin>(&mod_account, destination_addr, 10);
        assert!(coin::balance<MoonCoin>(source_addr) == 50, 1);
        assert!(coin::balance<MoonCoin>(destination_addr) == 10, 2);

        let supply = coin::supply<MoonCoin>();
        assert!(option::is_some(&supply), 1);
        assert!(option::extract(&mut supply) == 60, 2);

        coin::transfer<MoonCoin>(&source, destination_addr, 10);
        assert!(coin::balance<MoonCoin>(source_addr) == 40, 3);
        assert!(coin::balance<MoonCoin>(destination_addr) == 20, 4);

        coin::transfer<MoonCoin>(&source, signer::address_of(&mod_account), 40);
        burn<MoonCoin>(&mod_account, 40);

        assert!(coin::balance<MoonCoin>(source_addr) == 0, 1);

        let new_supply = coin::supply<MoonCoin>();
        assert!(option::extract(&mut new_supply) == 20, 2);
    }

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @basedao_addr)]
    #[expected_failure(abort_code = 0x60001, location = Self)]
    public entry fun fail_mint(
        source: signer,
        destination: signer,
        mod_account: signer,
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);

        aptos_framework::account::create_account_for_test(source_addr);
        aptos_framework::account::create_account_for_test(signer::address_of(&destination));
        aptos_framework::account::create_account_for_test(signer::address_of(&mod_account));

        initialize<MoonCoin>(&mod_account, b"Moon Coin", b"MOON", 1, true);
        coin::register<MoonCoin>(&mod_account);
        register<MoonCoin>(&source);
        register<MoonCoin>(&destination);

        mint<MoonCoin>(&destination, source_addr, 100);
    }

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @basedao_addr)]
    #[expected_failure(abort_code = 0x60001, location = Self)]
    public entry fun fail_burn(
        source: signer,
        destination: signer,
        mod_account: signer,
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);

        aptos_framework::account::create_account_for_test(source_addr);
        aptos_framework::account::create_account_for_test(signer::address_of(&destination));
        aptos_framework::account::create_account_for_test(signer::address_of(&mod_account));

        initialize<MoonCoin>(&mod_account, b"Moon Coin", b"MOON", 1, true);
        coin::register<MoonCoin>(&mod_account);
        register<MoonCoin>(&source);
        register<MoonCoin>(&destination);

        mint<MoonCoin>(&mod_account, source_addr, 100);
        burn<MoonCoin>(&destination, 10);
    }
}