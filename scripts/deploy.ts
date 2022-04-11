import { ethers } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { config as dotenvConfig } from 'dotenv';
import { resolve } from 'path';

dotenvConfig({ path: resolve(__dirname, '../.env') });

const token_details = {
    tokenName: 'OneOf Foundation DAO',
    tokenSymbol: 'ONEOF',    
    owner: `0xdc623afc7Ee320853D5E5D1Ca4f426a966dff67C`,
};

async function main(): Promise<void> {
    const { tokenName, tokenSymbol, owner } = token_details;
    //const MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    const MAX_UINT = 1_000_000_000_000_000_000;
    const Factory: ContractFactory = await ethers.getContractFactory('OneOfToken');            
    console.log(`Token name:${tokenName} (${tokenSymbol})`);
    console.log(`initialSupply:${MAX_UINT}, owner:${owner}`);            
    const Token: Contract = await Factory.deploy(
        tokenName,
        tokenSymbol,        
        owner,        
        owner,                
    );
    const deployed = await Token.deployed();
    console.log(`Contract deployed to:`, Token.address); 
    console.log(deployed);            
    const { deployTransaction } = deployed;
    const { hash, from, to, gasPrice, gasLimit, data, chainId, confirmations } = deployTransaction;
    console.log(`transaction id:${hash}`);
    console.log(`from:${from}, to:${to} - (${confirmations} confirmations)`);
    console.log(gasPrice, gasLimit);            
    console.log(`Verify using:` + `\n` + 
        `npx hardhat verify --network rinkeby ` + `${Token.address} ` + 
        `"${tokenName}" "${tokenSymbol}" "${owner}" "${owner}"`
        );    
};

/* We recommend this pattern to be able to use async/await everywhere
  and properly handle errors. */
main()
    .then(() => process.exit(0))
    .catch((error: Error) => {
        console.error(error);
        process.exit(1);
    });
