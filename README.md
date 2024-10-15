# BaseDAO

***Collectively building the future ecosystem on Aptos***

BaseDAO simplifies the creation and management of Decentralized Autonomous Organisations (DAOs) on the Aptos blockchain. 

With just one click, anyone can establish a DAO for their community, choosing a governance model that aligns closest with their group’s unique needs and preferences. 

As the New York Times describes, "a DAO (pronounced dow) is a relatively new kind of organisational structure, built with blockchain technology, that is often described as a sort of crypto co-op.”  

While DAOs originated within the crypto and blockchain space, their applications extend to a variety of real-world domains, such as life sciences with LabDAO and humanitarian projects through Impact DAOs. 

As technology and the world evolves, DAOs have become an essential tool for decentralised governance that can support a wide range of purposes — from investment groups to project collaborations, and even initiatives aimed at global change. 

![BaseDAO](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729011133/home-1_u6wloc.png)

## DAO Models for Different Community Needs

BaseDAO offers various governance models to suit different types of communities:

**Standard DAO**: This model supports collective decision-making, allowing members that hold the DAO’s governance tokens to participate in proposing, voting on, and executing ideas together.

**Guild DAO**: Designed for specialised and focused groups, the Guild DAO model incorporates a centralized leadership structure without the need for governance tokens, making it a good fit for small to medium communities.

**Hybrid DAO**: For communities that want a blend of democratic governance and role-based structures, the Hybrid DAO model offers flexibility with governance tokens and member roles together that influences a member’s vote and participation.

With BaseDAO, we want to abstract away the technical complexities, making it extremely easy for anyone to set up and manage a DAO, regardless of their technical expertise — so they can focus on what truly matters: building their community. 

![DAO models](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729011157/dao-models-1_r2eaoi.png)

## Governance Process and Proposal Types

BaseDAO allows each DAO to tailor its governance mechanisms to fit its unique structure. 

A core element of this customization is Proposal Types, which control aspects such as the duration of a proposal, the required percentage of votes from the total governance token supply for execution, and the minimum amount needed to either vote or create a proposal of the given type.

Upon initialisation, each DAO is currently provided with a default Proposal Type. However, looking ahead, we plan to introduce two additional default Proposal Types to cater to various scenarios. 

For instance, DAOs could utilize quick proposals to gauge community sentiment on specific issues or longer proposals requiring a higher success threshold for serious topics that warrant extended discussion.

Proposal Types themselves can be added, modified, or removed through governance actions. In addition, in Guild DAOs and Hybrid DAOs, members holding leader roles (or those with a vote weight equal to or greater than the leader's minimum threshold) will be able to customise proposal types as well.

Once a proposal accumulates sufficient YAY votes to surpass the success threshold, any member can execute it. For example, if a Fungible Asset transfer proposal is executed successfully, it will trigger a transfer from the DAO module to the intended recipient with the specified amount in the proposal.

This execution mechanism applies to all proposal types except the standard proposal, which is intended for general discussions and polls rather than on-chain actions.

Through these flexible and customisable mechanisms, various groups and organisations will be able to utilise the DAO models on BaseDAO to suit their needs and purposes.

## Demo MVP

The BaseDAO demo is accessible at [https://aptosbasedao.com](https://aptosbasedao.com) on the Aptos Testnet. The demo showcases sample DAOs from the various DAO models.

**Features**:
- **Wallet Integration**: Users can connect their Aptos wallets to interact with the platform on the Aptos Testnet.

- **Sample DAOs**: Explore sample daos with detailed descriptions, images, and proposals

- **Faucet**: Users will be able to mint our governance tokens on the testnet to interact with our sample DAOS

- **Create Proposal**: Users are free to experiment and create proposals of their own on the Aptos Testnet

- **Vote for Proposal**: Users will be able to use governance tokens that they have minted to vote for proposals (Standard / Hybrid DAOs)

- **Real-Time Updates**: Successful votes will automatically update the proposal vote count

Our interactive demo provides a comprehensive preview of the BaseDAO platform. Users can explore sample DAOs with detailed descriptions, images, and proposals to get a feel for how the live site will operate.

We also prioritise the user journey in both funding and supporting campaigns, making the process straightforward and accessible. 

Once a vote is successfully made and the transaction is recorded on the blockchain, the proposal's progress updates automatically to reflect the new vote count.

The frontend demo for BaseDao is maintained in a separate repository to ensure that the Move contracts remain focused and well-organised.

It can be found here: [BaseDAO Frontend Github](https://github.com)

Screenshot of sample DAOs:


## Tech Overview and Considerations

We follow the Aptos Object Model approach, storing Proposals on user accounts rather than on the DAO contract to decentralise data storage, enhance scalability, and optimise gas costs. 

The DAO contract maintains a ProposalRegistry struct that maps proposal IDs to their respective creators. Proposal IDs are unique and sequentially assigned, ensuring that no two proposals share the same ID, regardless of their creator.

As there is no factory pattern available on Aptos Move, compared to Solidity, where we can initialise a new module or smart contract from another, we adopt an unconventional approach to pre-generate DAO modules that can then be initialised.

A DAO module can only be initialised once, preventing any possible conflicts. To help with this approach, we have developed a DAO generator Python script that will be able to rapidly deploy any number of DAOs using an Aptos CLI subprocess. In the future, we plan to integrate this with a server so that a new DAO module can be generated on-demand when required instead.

## Smart Contract Entrypoints

The BaseDAO DAO module entrypoints includes eleven public entrypoints that are common to each of the DAO models (standard, guild, and hybrid):

**General DAO Entrypoints**

1. **init_dao**: Initialises a new DAO. This can only be called once. 
   - **Input**: DAO name, description, image, and governance token metadata
   - **Output**: Initialises a DAO on the given module

2. **deposit_fa_to_dao**: Deposits a specified fungible asset to the DAO module
   - **Input**: Depositor signer, amount, and fungible asset token metadata
   - **Output**: Transfers tokens from the depositor to the DAO

3. **deposit_coin_to_dao**: Deposits a specified coin to the DAO module
   - **Input**: Depositor signer and amount,
   - **Output**: Transfers coins from the depositor to the DAO

4. **create_fa_transfer_proposal**: Creates a proposal to transfer fungible assets
   - **Input**: Proposal title, description, proposal type, and FA transfer parameters
   - **Output**: Creates new FA transfer proposal

5. **create_coin_transfer_proposal**: Creates a proposal to transfer coins
   - **Input**: Proposal title, description, proposal type, and coin transfer parameters
   - **Output**: Creates new coin transfer proposal

6. **create_proposal_update_proposal**: Creates a proposal to update or remove proposal types 
    - **Input**: Proposal title, description, proposal type, and new proposal type parameters
    - **Output**: Creates new proposal update proposal

7. **create_dao_update_proposal**: Creates a proposal to update the DAO info
   - **Input**: Proposal title, description, proposal type, and new DAO info (name, description, image)
   - **Output**: Creates new DAO update proposal

8. **create_standard_proposal**: Creates a standard miscellaneous proposal to get members voting preferences on an issue
   - **Input**: Proposal title, description, proposal type
   - **Output**: Creates new standard proposal

9. **vote_for_proposal**: Allows a user to vote for a given proposal if he has sufficient governance tokens above the threshold specified in the proposal type 
   - **Input**: Voter, proposal ID and vote type 
   - **Output**: Votes on a proposal

10. **execute_proposal**: Allows a user to executes a proposal if it has garnered sufficient votes. If insufficient votes were gathered, the proposal result would be marked as "FAIL"
   - **Input**: Proposal ID
   - **Output**: Executes a proposal

11. **execute_coin_transfer_proposal**: Allows a user to executes a coin transfer proposal if it has garnered sufficient votes. If insufficient votes were gathered, the proposal result would be marked as "FAIL"
   - **Input**: Proposal ID and a given CoinType that should match the proposal to be executed
   - **Output**: Executes a coin transfer proposal

</br>

---

</br>
In addition, for the Guild and Hybrid DAO, there are 8 access-controlled entrypoints that allow executives and leaders to add or update roles, members, proposal types and access level vote weights required.

</br>

**Additional Guild/Hybrid DAO Entrypoints**

**Leader Role Entrypoints:**

12. **update_executive_vote_weight**: Allows leaders with sufficient vote weight above or equal to min_leader_vote_weight to update the min_executive_vote_weight for member access to executive-level entrypoints
   - **Input**: Leader signer and new min_executive_vote_weight
   - **Output**: Updates the min_executive_vote_weight

13. **update_leader_vote_weight**: Allows leaders with sufficient vote weight above or equal to min_leader_vote_weight to update the min_leader_vote_weight for member access to leader-level entrypoints
   - **Input**: Leader signer and new min_leader_vote_weight
   - **Output**: Updates the min_leader_vote_weight

14. **add_or_update_proposal_types**: Allows leaders to add or update proposal types
   - **Input**: Leader signer and new proposal type parameters
   - **Output**: Creates or updates a new proposal type

15. **remove_proposal_types**: Allows leaders to remove proposal types
   - **Input**: Leader signer and proposal type name
   - **Output**: Removes a new proposal type

**Executive Role Entrypoints:**

16. **add_or_update_role**: Allows leaders or executives to add or update roles
   - **Input**: Executive signer, role, and role weight
   - **Output**: Creates or updates a role

17. **remove_role**: Allows leaders or executives to remove roles
   - **Input**: Executive signer and role name
   - **Output**: Removes a role

18. **add_or_update_member**: Allows leaders or executives to add or update members
   - **Input**: Executive signer, member address, and member role
   - **Output**: Creates or updates the given member with the given member role

19. **remove_member**: Allows leaders or executives to remove members
   - **Input**: Executive signer and member address
   - **Output**: Removes the given member 

## Code Coverage

BaseDAO has comprehensive test coverage, with 100% of the codebase thoroughly tested. This includes a full range of scenarios that ensure the platform's reliability and robustness. 

The following section provides a breakdown of the tests that validate each function and feature, affirming that BaseDAO performs as expected under all intended use cases.

Complete code coverage of 5 modules, including 3 DAO modules, one governance token, and one sample coin token

![Complete Code Coverage](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729011348/complete-code-coverage-1_vnpl3p.png)

Code Coverage for Standard DAO at 100%

![Standard DAO Coverage](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729012076/standard-dao-code-coverage_dfderi.png)


Code Coverage for Guild DAO at 100%

![Guild DAO Coverage](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729012076/guild-dao-code-coverage_vnxt4l.png)


Code Coverage for Hybrid DAO at 100%

![Hybrid DAO Coverage](https://res.cloudinary.com/blockbard/image/upload/c_scale,w_auto,q_auto,f_auto,fl_lossy/v1729012076/hybrid-dao-code-coverage_dkdmjy.png)


## Dummy Data Script

We have also included a dummy data script to populate the BaseDAO Demo MVP with 9 sample DAOs. This helps to demonstrate our features and provides a realistic view of how DAOs appear and function on the site.

However, do take note that you will have to run the BaseDAO generator script to deploy some DAO modules first before running the script below.

To run the dummy data script after deploying a local instance of our frontend and BaseDAO Package, follow these steps:

```
# compile the dummy data script and get the script path location
aptos move compile-script

# copy the script path location and paste it at the end (replace path_to_script.mv)
aptos move run-script --compiled-script-path /path_to_script.mv
```

## Future Plans

Looking ahead, here are some plans to expand the features and capabilities of BaseDAO in Phase 2.

### Planned Features:

- **Expand DAO Governance Models**: As more communities adopt decentralized governance, BaseDAO aims to expand its offering with additional governance models tailored for specific use cases. For example, a “Quadratic Voting DAO” could cater to communities interested in nuanced decision-making, while a “DAO-as-a-Service” model could support organizations needing turnkey solutions for various governance structures.

- **Launch DAO Toolkits for Community Management**: With a growing user base, we would also be able to develop and launch a suite of community management tools, including event scheduling, treasury management, and collaboration features. These toolkits will provide a comprehensive set of resources for communities to thrive and grow further.

- **Onboarding and Education Programs**: As DAOs continue to grow in popularity, BaseDAO will prioritize education and onboarding resources to help new users understand the value of decentralized governance. These programs could include workshops, tutorials, and online courses focused on DAO creation, governance best practices, and community engagement strategies.

With the development of these planned features, we hope that BaseDAO will become a one-stop platform for all things DAO-related on Aptos.

## Conclusion

BaseDAO is committed to lowering the barriers to decentralized governance, enabling anyone to build and manage a DAO with ease on Aptos. 

By expanding our governance models, enhancing integrations, and offering robust community tools, BaseDAO seeks to be the go-to platform for DAO creation and management. 

As the world continues to embrace decentralized technologies, BaseDAO will be at the forefront, empowering communities to build, collaborate, and drive meaningful change.

## Credits and Support

Thanks for reading till the end!

BaseDAO is designed and built by 0xBlockBard, a solo indie maker passionate about building innovative products in the web3 space. 

With over 10 years of experience, my work spans full-stack and smart contract development, with the Laravel Framework as my go-to for web projects. I’m also familiar with Solidity, Rust, LIGO, and most recently, Aptos Move.

Beyond coding, I occasionally write and share insights on crypto market trends and interesting projects to watch. If you are interested to follow along my web3 journey, you can subscribe to my [Substack](https://www.0xblockbard.com/) here :)

Twitter / X: [0xBlockBard](https://x.com/0xblockbard)

Substack: [0xBlockBard Research](https://www.0xblockbard.com/)