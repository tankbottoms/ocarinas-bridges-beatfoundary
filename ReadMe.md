# OneOf Ethereum Token

<p align="center"></p>

# Deploy

After cloning the repository, install, build, and compile contract and run test.

```bash
yarn && yarn run build && yarn run compile && yarn run test
npx hardhat run --network rinkeby ./scripts/deploy.ts
```

The deployment should return an address, for example, here is what I received.

```bash
0x2D158DfF69097af8941E6a06E634B0F0A8c836Cf
```

Compare the deployment constructor arguments, which I referenced from `config/index.ts` and either use the `arguments.js` or pass into the following function verbatim.The following will verify the contract, in effect, publish the source code on Etherscan.

```bash
npx hardhat verify --network rinkeby [ETH_ADDRESS'] "TOKEN_NAME" "SYMBOL" MAX_COUNT START_DATE
```
