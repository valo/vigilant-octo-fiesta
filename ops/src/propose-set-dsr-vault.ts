import dotenv from 'dotenv';
import path from 'node:path';
import { encodeFunctionData, isAddress, zeroAddress } from 'viem';

import { loadAbi } from './helpers/abi';
import { getSafeInstances } from './helpers/safe';

// Load ops/.env first (CHAIN_ID, SAFE_ADDRESS, etc), then fall back to repo-root .env (SYNTH_ADDRESS, SAVINGS_RATE_ADDRESS).
dotenv.config({ path: path.resolve(process.cwd(), '.env'), override: false });
dotenv.config({ path: path.resolve(process.cwd(), '..', '.env'), override: false });

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

function readCliArgs(): { savingsRateModule?: `0x${string}` } {
    const args = process.argv.slice(2);
    if (args.length === 0) {
        return {};
    }

    if (args.length !== 1) {
        console.error(
            'Invalid arguments. Usage:\n' +
                '  pnpm --dir ops run propose:set-dsr-vault\n' +
                '  pnpm --dir ops run propose:set-dsr-vault -- <savingsRateModuleAddress>\n' +
                'Example:\n' +
                '  pnpm --dir ops run propose:set-dsr-vault -- 0xabc...def'
        );
        process.exit(1);
    }

    const [savingsRateModuleRaw] = args;
    if (!isAddress(savingsRateModuleRaw) || savingsRateModuleRaw === zeroAddress) {
        throw new Error(`Invalid SavingsRateModule address: ${savingsRateModuleRaw}`);
    }

    return { savingsRateModule: savingsRateModuleRaw as `0x${string}` };
}

async function main() {
    const chainIdRaw = requireEnv('CHAIN_ID');
    const chainId = Number(chainIdRaw);
    if (Number.isNaN(chainId)) {
        throw new Error(`Invalid CHAIN_ID provided: ${chainIdRaw}`);
    }

    const safeAddress = requireEnv('SAFE_ADDRESS');

    const synthAddressRaw = requireEnv('SYNTH_ADDRESS');
    if (!isAddress(synthAddressRaw) || synthAddressRaw === zeroAddress) {
        throw new Error(`Invalid SYNTH_ADDRESS provided: ${synthAddressRaw}`);
    }
    const synthAddress = synthAddressRaw as `0x${string}`;

    const envSavingsRateRaw = requireEnv('SAVINGS_RATE_ADDRESS');
    if (!isAddress(envSavingsRateRaw) || envSavingsRateRaw === zeroAddress) {
        throw new Error(`Invalid SAVINGS_RATE_ADDRESS provided: ${envSavingsRateRaw}`);
    }
    const envSavingsRateModule = envSavingsRateRaw as `0x${string}`;

    const { savingsRateModule } = readCliArgs();
    const targetSavingsRateModule = savingsRateModule ?? envSavingsRateModule;

    const nusdAbi = loadAbi('../out/nUSD.sol/nUSD.json');

    const data = encodeFunctionData({
        abi: nusdAbi,
        functionName: 'setDsrVault',
        args: [targetSavingsRateModule],
    });

    const { safe, apiKit, signer } = await getSafeInstances(safeAddress, chainId);
    const signerAddress = await signer.getAddress();

    const safeTx = await safe.createTransaction({
        transactions: [{ to: synthAddress, data, value: '0' }],
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

    console.log(`Proposed setDsrVault(${targetSavingsRateModule}) on dfUSD ${synthAddress} from Safe ${safeAddress}`);
    console.log(`Sender: ${signerAddress}`);
    console.log(`Tx hash: ${safeTxHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
