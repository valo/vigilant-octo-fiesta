// ops/src/propose-ltv.ts
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

function parseUint(input: string, label: string, max: number): number {
    const value = Number(input);
    if (!Number.isFinite(value) || value < 0) {
        throw new Error(`${label} must be a non-negative number`);
    }
    if (value > max) {
        throw new Error(`${label} exceeds maximum (${max})`);
    }
    return value;
}

function readCliArgs(): {
    collateralVault: `0x${string}`;
    borrowLtv: number;
    liquidationLtv: number;
    rampDuration: number;
} {
    const args = process.argv.slice(2);
    if (args.length < 4) {
        console.error(
            'Missing arguments. Usage:\n' +
            '  pnpm --dir ops run propose:ltv -- <collateralVault> <borrowLTV_bps> <liquidationLTV_bps> <rampDurationSeconds>\n' +
            'Example:\n' +
            '  pnpm --dir ops run propose:ltv -- 0xabc...def 800 850 1800'
        );
        process.exit(1);
    }

    const [vaultRaw, borrowLtvRaw, liquidationLtvRaw, rampDurationRaw] = args;
    if (!isAddress(vaultRaw)) {
        throw new Error(`Invalid collateral vault address: ${vaultRaw}`);
    }

    const borrowLtv = parseUint(borrowLtvRaw, 'borrowLTV', 10_000);
    const liquidationLtv = parseUint(liquidationLtvRaw, 'liquidationLTV', 10_000);
    const rampDuration = parseUint(rampDurationRaw, 'rampDuration', 0xffffffff);

    return {
        collateralVault: vaultRaw as `0x${string}`,
        borrowLtv,
        liquidationLtv,
        rampDuration,
    };
}

async function main() {
    const chainIdRaw = requireEnv('CHAIN_ID');
    const chainId = Number(chainIdRaw);
    if (Number.isNaN(chainId)) {
        throw new Error(`Invalid CHAIN_ID provided: ${chainIdRaw}`);
    }

    const safeAddress = requireEnv('SAFE_ADDRESS');
    const nUSDVaultAddress = requireEnv('NUSD_VAULT_ADDRESS');
    if (!isAddress(nUSDVaultAddress)) {
        throw new Error(`Invalid nUSD vault address: ${nUSDVaultAddress}`);
    }

    const { collateralVault, borrowLtv, liquidationLtv, rampDuration } = readCliArgs();

    const vaultAbi = loadAbi('../out/EVault.sol/EVault.json');

    const data = encodeFunctionData({
        abi: vaultAbi,
        functionName: 'setLTV',
        args: [collateralVault, borrowLtv, liquidationLtv, rampDuration],
    });

    const { safe, apiKit, signer } = await getSafeInstances(safeAddress, chainId);
    const signerAddress = await signer.getAddress();

    const safeTx = await safe.createTransaction({
        transactions: [{ to: nUSDVaultAddress, data, value: '0' }],
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

    console.log(
        `Proposed setLTV(${collateralVault}, ${borrowLtv}, ${liquidationLtv}, ${rampDuration}) to nUSD vault ${nUSDVaultAddress} from Safe ${safeAddress}`
    );
    console.log(`Sender: ${signerAddress}`);
    console.log(`Tx hash: ${safeTxHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
