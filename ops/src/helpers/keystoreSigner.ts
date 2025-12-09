// ops/src/helpers/keystoreSigner.ts
import fs from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { Writable } from 'node:stream';
import { JsonRpcProvider, Wallet } from 'ethers';

class MaskedStdout extends Writable {
    private masked = false;

    mute() {
        this.masked = true;
    }

    unmute() {
        this.masked = false;
    }

    _write(chunk: Buffer, encoding: BufferEncoding, callback: (error?: Error | null) => void) {
        const text = chunk.toString('utf8');
        if (this.masked) {
            output.write(text.replace(/[^\n\r]/g, '*'));
        } else {
            output.write(text);
        }
        callback();
    }
}

async function promptHidden(query: string): Promise<string> {
    const maskedOutput = new MaskedStdout();
    const rl = createInterface({ input, output: maskedOutput, terminal: true });
    output.write(query);
    maskedOutput.mute();
    const answer = await rl.question('');
    maskedOutput.unmute();
    await rl.close();
    output.write('\n');
    return answer;
}

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

    const envPassword = process.env.ETH_PASSWORD;
    const password = envPassword ?? (await promptHidden('Keystore password: '));
    const wallet = await Wallet.fromEncryptedJson(json, password);
    return wallet.connect(new JsonRpcProvider(rpcUrl));
}
