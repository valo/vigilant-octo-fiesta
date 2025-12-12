// ops/src/propose-synth-collateral.ts
import 'dotenv/config';
import { encodeFunctionData, isAddress } from 'viem';

import { loadAbi } from './helpers/abi';
import { getSafeInstances, rpc } from './helpers/safe';

const erc4626Abi = [
    {
        name: 'asset',
        type: 'function',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'address' }],
    },
] as const;

const synthVaultAbi = [
    {
        name: 'oracle',
        type: 'function',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'address' }],
    },
    {
        name: 'unitOfAccount',
        type: 'function',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'address' }],
    },
] as const;

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

function requireEnvWithFallback(primary: string, fallback?: string): string {
    const primaryValue = process.env[primary];
    if (primaryValue) return primaryValue;
    if (fallback) {
        const fallbackValue = process.env[fallback];
        if (fallbackValue) return fallbackValue;
    }
    throw new Error(`Missing required env var: ${primary}${fallback ? ` (fallback: ${fallback})` : ''}`);
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
    priceOracle: `0x${string}`;
    borrowLtv: number;
    liquidationLtv: number;
    rampDuration: number;
} {
    const args = process.argv.slice(2);
    if (args.length < 5) {
        console.error(
            'Missing arguments. Usage:\n' +
            '  pnpm --dir ops run propose:synth-collateral -- <collateralVault> <oracleAddress> <borrowLTV_bps> <liquidationLTV_bps> <rampDurationSeconds>\n' +
            'Example:\n' +
            '  pnpm --dir ops run propose:synth-collateral -- 0xabc...def 0xoracle... 7500 8000 1800'
        );
        process.exit(1);
    }

    const [vaultRaw, oracleRaw, borrowLtvRaw, liquidationLtvRaw, rampDurationRaw] = args;
    if (!isAddress(vaultRaw)) {
        throw new Error(`Invalid collateral vault address: ${vaultRaw}`);
    }
    if (!isAddress(oracleRaw)) {
        throw new Error(`Invalid oracle address: ${oracleRaw}`);
    }

    const borrowLtv = parseUint(borrowLtvRaw, 'borrowLTV', 10_000);
    const liquidationLtv = parseUint(liquidationLtvRaw, 'liquidationLTV', 10_000);
    const rampDuration = parseUint(rampDurationRaw, 'rampDuration', 0xffffffff);

    return {
        collateralVault: vaultRaw as `0x${string}`,
        priceOracle: oracleRaw as `0x${string}`,
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
    const synthVaultAddress = requireEnvWithFallback('SYNTH_VAULT_ADDRESS', 'NUSD_VAULT_ADDRESS');
    if (!isAddress(synthVaultAddress)) {
        throw new Error(`Invalid synth vault address: ${synthVaultAddress}`);
    }

    const { collateralVault, priceOracle, borrowLtv, liquidationLtv, rampDuration } = readCliArgs();
    const publicClient = rpc(chainId);
    const synthOracleAddress = await publicClient.readContract({
        address: synthVaultAddress as `0x${string}`,
        abi: synthVaultAbi,
        functionName: 'oracle',
    });
    if (!isAddress(synthOracleAddress)) {
        throw new Error(`Invalid synth oracle address returned from vault: ${synthOracleAddress}`);
    }

    const unitOfAccount = await publicClient.readContract({
        address: synthVaultAddress as `0x${string}`,
        abi: synthVaultAbi,
        functionName: 'unitOfAccount',
    });
    if (!isAddress(unitOfAccount)) {
        throw new Error(`Invalid unit of account address returned from vault: ${unitOfAccount}`);
    }

    const collateralAsset = await publicClient.readContract({
        address: collateralVault,
        abi: erc4626Abi,
        functionName: 'asset',
    });

    const vaultAbi = loadAbi('../out/EVault.sol/EVault.json');
    const routerAbi = loadAbi('../out/EulerRouter.sol/EulerRouter.json');

    const setLtvData = encodeFunctionData({
        abi: vaultAbi,
        functionName: 'setLTV',
        args: [collateralVault, borrowLtv, liquidationLtv, rampDuration],
    });

    const setOracleData = encodeFunctionData({
        abi: routerAbi,
        functionName: 'govSetConfig',
        args: [collateralAsset, unitOfAccount, priceOracle],
    });

    const setResolvedVaultData = encodeFunctionData({
        abi: routerAbi,
        functionName: 'govSetResolvedVault',
        args: [collateralVault, true],
    });

    const { safe, apiKit, signer } = await getSafeInstances(safeAddress, chainId);
    const signerAddress = await signer.getAddress();

    const safeTx = await safe.createTransaction({
        transactions: [
            { to: synthVaultAddress, data: setLtvData, value: '0' },
            { to: synthOracleAddress, data: setOracleData, value: '0' },
            { to: synthOracleAddress, data: setResolvedVaultData, value: '0' },
        ],
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

    console.log('Prepared transactions:');
    console.log(`- setLTV(${collateralVault}, ${borrowLtv}, ${liquidationLtv}, ${rampDuration}) on synth vault ${synthVaultAddress}`);
    console.log(`- govSetConfig(${collateralAsset}, ${unitOfAccount}, ${priceOracle}) on router ${synthOracleAddress}`);
    console.log(`- govSetResolvedVault(${collateralVault}, true) on router ${synthOracleAddress}`);
    console.log(`Proposed from Safe ${safeAddress}`);
    console.log(`Sender: ${signerAddress}`);
    console.log(`Tx hash: ${safeTxHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
