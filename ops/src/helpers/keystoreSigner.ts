// ops/src/helpers/keystoreSigner.ts
import fs from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { JsonRpcProvider, Wallet } from 'ethers';

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

export async function getSignerFromKeystore() {
    const keystorePath = requireEnv('ETH_KEYSTORE_PATH');
    const rpcUrl = requireEnv('RPC_URL');
    const json = fs.readFileSync(keystorePath, 'utf8');

    const rl = createInterface({ input, output });
    const envPassword = process.env.ETH_PASSWORD;
    const password = envPassword ?? (await rl.question('Keystore password: '));
    await rl.close();

    const wallet = await Wallet.fromEncryptedJson(json, password);
    return wallet.connect(new JsonRpcProvider(rpcUrl));
}
