# Fabric Smart Contracts

This repository contains all Fabric protocol source code. You can find documentation [here](https://docs.withfabric.xyz/).

### Setup

Foundry tooling is used for testing and compiling contracts. Run the setup
script to install and update it.

```
./script/setup
```

### Testing

```
forge test -vvv
```

Other useful tools

```
forge coverage
forge fmt
forge doc
```

### Signing Commits

All commits and tags for this repository should be signed.

To deploy the Subscription Factory contract, use the following command:

```
forge script script/DeploySubscriptionFactory.s.sol:DeploySubscriptionFactory --rpc-url YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY --broadcast --verify --etherscan-api-key BLOCK_SCANNER_API_KEY -vvvv
```
