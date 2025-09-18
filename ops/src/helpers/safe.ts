// ops/src/helpers/safe.ts
import Safe from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import { createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';

import { getSignerFromKeystore } from './keystoreSigner';

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

export function rpc(chainId: number) {
    const url = requireEnv('RPC_URL');
    return createPublicClient({ chain: { ...sepolia, id: chainId }, transport: http(url) });
}

export async function getSafeInstances(safeAddress: string, chainId: number) {
    const rpcUrl = requireEnv('RPC_URL');
    const signer = await getSignerFromKeystore();

    const safe = await Safe.init({
        provider: rpcUrl,
        signer: signer.privateKey,
        safeAddress,
    });

    const apiKey = requireEnv('SAFE_TX_SERVICE_API_KEY');
    const apiKit = new SafeApiKit({ chainId: BigInt(chainId), apiKey });

    return { safe, apiKit, signer } as const;
}
