// ops/src/helpers/abi.ts
import fs from 'node:fs';

export function loadAbi(path: string): readonly unknown[] {
    const artifact = JSON.parse(fs.readFileSync(path, 'utf8')) as { abi: readonly unknown[] };
    return artifact.abi;
}
