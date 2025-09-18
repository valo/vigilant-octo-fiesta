// ops/src/propose-psm-fees.ts
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

function parseFee(input: string, label: string): bigint {
    try {
        const fee = BigInt(input);
        if (fee < 0n) {
            throw new Error(`${label} must be non-negative`);
        }
        return fee;
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`Invalid ${label} fee: ${message}`);
    }
}

function readCliArgs(): { target: `0x${string}`; underlyingFee: bigint; synthFee: bigint } {
    const args = process.argv.slice(2);
    if (args.length < 3) {
        console.error(
            'Missing arguments. Usage:\n' +
            '  pnpm --dir ops run propose:psm-fees -- <psmAddress> <underlyingFeeBps> <synthFeeBps>\n' +
            'Example:\n' +
            '  pnpm --dir ops run propose:psm-fees -- 0xabc...def 10 25'
        );
        process.exit(1);
    }

    const [targetRaw, underlyingFeeRaw, synthFeeRaw] = args;
    if (!isAddress(targetRaw)) {
        throw new Error(`Invalid PSM module address: ${targetRaw}`);
    }

    const underlyingFee = parseFee(underlyingFeeRaw, 'underlying');
    const synthFee = parseFee(synthFeeRaw, 'synth');

    return { target: targetRaw as `0x${string}`, underlyingFee, synthFee };
}

async function main() {
    const chainIdRaw = requireEnv('CHAIN_ID');
    const chainId = Number(chainIdRaw);
    if (Number.isNaN(chainId)) {
        throw new Error(`Invalid CHAIN_ID provided: ${chainIdRaw}`);
    }

    const safeAddress = requireEnv('SAFE_ADDRESS');
    const { target, underlyingFee, synthFee } = readCliArgs();

    const psmAbi = loadAbi('../out/PegStabilityModule.sol/PegStabilityModule.json');

    const data = encodeFunctionData({
        abi: psmAbi,
        functionName: 'setFees',
        args: [underlyingFee, synthFee],
    });

    const { safe, apiKit, signer } = await getSafeInstances(safeAddress, chainId);
    const signerAddress = await signer.getAddress();

    const safeTx = await safe.createTransaction({
        transactions: [{ to: target, data, value: '0' }],
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

    console.log(`Proposed setFees(${underlyingFee}, ${synthFee}) to ${target} from Safe ${safeAddress}`);
    console.log(`Sender: ${signerAddress}`);
    console.log(`Tx hash: ${safeTxHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
