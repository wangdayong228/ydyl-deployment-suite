const path = require('path');
const { Conflux, Drip, address } = require('js-conflux-sdk');
const ethers = require('ethers');
require('dotenv').config({ path: path.join(__dirname, '.env') });

function requireEnv(name) {
    const value = String(process.env[name] || '').trim();
    if (!value) throw new Error(`必须设置 ${name}`);
    return value;
}

function parseAmountCfx() {
    const raw = process.env.AMOUNT || process.argv[2] || '10000';
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`amount 必须是正数，当前: ${raw}`);
    }
    return String(raw);
}

const privateKey = process.env.PRIVATE_KEY;
if (!privateKey || !/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
    throw new Error('必须设置 PRIVATE_KEY，格式为 0x 加 64 位十六进制');
}

const eSpaceRpc = requireEnv('ESPACE_RPC');
const cSpaceRpc = process.env.CSPACE_RPC || process.env.CORE_RPC;
if (!String(cSpaceRpc || '').trim()) {
    throw new Error('必须设置 CSPACE_RPC 或 CORE_RPC');
}

async function main() {
    const amountCfx = parseAmountCfx();
    const toTransfer = ethers.parseEther(amountCfx);

    const provider = new ethers.JsonRpcProvider(eSpaceRpc);
    const cfx = await Conflux.create({ url: cSpaceRpc });
    const account = cfx.wallet.addPrivateKey(privateKey);
    const signer = new ethers.Wallet(privateKey, provider);
    const mapped = address.cfxMappedEVMSpaceAddress(account.address);
    const Cross = cfx.InternalContract('CrossSpaceCall');

    const eSpaceBefore = await provider.getBalance(signer.address);
    const coreBefore = await cfx.getBalance(account.address);
    const mappedBefore = await Cross.mappedBalance(account.address);

    console.log(`ESPACE_RPC ${eSpaceRpc}`);
    console.log(`CSPACE_RPC ${cSpaceRpc}`);
    console.log(`networkId  ${cfx.networkId}`);
    console.log(`amount     ${amountCfx} CFX`);
    console.log(`Core       ${account.address}: ${new Drip(coreBefore).toCFX()} CFX`);
    console.log(`eSpace     ${signer.address}: ${ethers.formatEther(eSpaceBefore)} CFX`);
    console.log(`mapped     ${mapped}: ${new Drip(mappedBefore).toCFX()} CFX`);

    const gasReserve = ethers.parseEther('1');
    if (eSpaceBefore < toTransfer + gasReserve) {
        throw new Error(
            `eSpace 余额不足：需要 ${amountCfx} CFX + 1 CFX gas，当前 ${ethers.formatEther(eSpaceBefore)} CFX`,
        );
    }

    console.log(`Step1: eSpace ${signer.address} -> mapped ${mapped}, ${amountCfx} CFX`);
    const tx = await signer.sendTransaction({
        to: mapped,
        value: toTransfer,
    });
    console.log(`eSpace tx: ${tx.hash}`);
    await tx.wait();

    const mappedAfter = await Cross.mappedBalance(account.address);
    console.log(`mapped after: ${new Drip(mappedAfter).toCFX()} CFX`);
    if (mappedAfter < toTransfer) {
        throw new Error(`mapped 余额不足 ${amountCfx} CFX，当前 ${new Drip(mappedAfter).toCFX()} CFX`);
    }

    console.log(`Step2: Core withdrawFromMapped ${amountCfx} CFX`);
    const receipt = await Cross.withdrawFromMapped(toTransfer).sendTransaction({
        from: account,
    }).executed();
    console.log(`Core withdraw outcomeStatus=${receipt.outcomeStatus}`);

    const eSpaceAfter = await provider.getBalance(signer.address);
    const coreAfter = await cfx.getBalance(account.address);
    console.log(`Core after   ${new Drip(coreAfter).toCFX()} CFX`);
    console.log(`eSpace after ${ethers.formatEther(eSpaceAfter)} CFX`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
