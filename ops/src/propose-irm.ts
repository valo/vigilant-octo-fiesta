// ops/src/propose-irm.ts
import 'dotenv/config';
import { encodeFunctionData, isAddress } from 'viem';

import { loadAbi } from './helpers/abi';
import { getSafeInstances } from './helpers/safe';

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

function readCliArgs(): { vault: `0x${string}`; irm: `0x${string}` } {
    const args = process.argv.slice(2);
    if (args.length < 2) {
        console.error(
            'Missing arguments. Usage:\n' +
            '  pnpm --dir ops run propose:irm -- <vaultAddress> <irmAddress>\n' +
            'Example:\n' +
            '  pnpm --dir ops run propose:irm -- 0xvault... 0xirm...'
        );
        process.exit(1);
    }

    const [vaultRaw, irmRaw] = args;
    if (!isAddress(vaultRaw)) {
        throw new Error(`Invalid vault address: ${vaultRaw}`);
    }
    if (!isAddress(irmRaw)) {
        throw new Error(`Invalid IRM address: ${irmRaw}`);
    }

    return { vault: vaultRaw as `0x${string}`, irm: irmRaw as `0x${string}` };
}

async function main() {
    const chainIdRaw = requireEnv('CHAIN_ID');
    const chainId = Number(chainIdRaw);
    if (Number.isNaN(chainId)) {
        throw new Error(`Invalid CHAIN_ID provided: ${chainIdRaw}`);
    }

    const safeAddress = requireEnv('SAFE_ADDRESS');
    const { vault, irm } = readCliArgs();

    const vaultAbi = loadAbi('../out/EVault.sol/EVault.json');

    const data = encodeFunctionData({
        abi: vaultAbi,
        functionName: 'setInterestRateModel',
        args: [irm],
    });

    const { safe, apiKit, signer } = await getSafeInstances(safeAddress, chainId);
    const signerAddress = await signer.getAddress();

    const safeTx = await safe.createTransaction({
        transactions: [{ to: vault, data, value: '0' }],
    });

    const safeTxHash = await safe.getTransactionHash(safeTx);
    const signature = await safe.signHash(safeTxHash);

    await apiKit.proposeTransaction({
        safeAddress,
        safeTransactionData: safeTx.data,
        safeTxHash,
        senderAddress: signerAddress,
        senderSignature: signature.data,
    });

    console.log(`Proposed setInterestRateModel(${irm}) on vault ${vault} from Safe ${safeAddress}`);
    console.log(`Sender: ${signerAddress}`);
    console.log(`Tx hash: ${safeTxHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
