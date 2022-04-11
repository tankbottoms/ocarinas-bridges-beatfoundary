import { Signer } from "@ethersproject/abstract-signer";
import { task } from "hardhat/config";

const PRIVATE_KEY = '';

export const createConfig = (
  network: keyof typeof chainIds,
): NetworkUserConfig => {    
  const url = `https://eth-${network}.alchemyapi.io/v2/` +
    `${process.env[`${network.toUpperCase()}_ALCHEMY_API_KEY`]}`;
  return {
    accounts: [`0x${PRIVATE_KEY}`],
    chainId: chainIds[network],
    url,
  };    
};
