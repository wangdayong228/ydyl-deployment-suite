const {Conflux, format, Drip} = require('js-conflux-sdk');
const ethers = require('ethers');

const provider = new ethers.JsonRpcProvider('http://34.219.245.189:8545');

const cfx = new Conflux({
    url: 'http://34.219.245.189:12537',
    networkId: 7654,
});

const privateKey = '0xb4810523501eec2591a2652c4394feb884129f78c940a2bf23efdf6046d08677' || process.env.ETH_PRIVATE_KEY;
const pk2 = '0x37398ebb49943b3326a7bb4e8c3aed4b3aed6c4b09b1b197b8c85a6686e774ad';
const pk3 = '0x53bfe542f225644873d7dfc74306e91c192e782f39d52e5b07dc4127dc6328b2';
const account = cfx.wallet.addPrivateKey(privateKey);
const account2 = cfx.wallet.addPrivateKey(pk2);
const account3 = cfx.wallet.addPrivateKey(pk3);
const signer = new ethers.Wallet(privateKey, provider);

async function main() {
	await transfer(account);
	await transfer(account2);
	await transfer(account3);
}

async function transfer(account) {
	let balance = await cfx.getBalance(account.address);
    console.log(`Balance of ${account.address}: ${new Drip(balance).toCFX()} CFX`);

    let target = signer.address;

    let toTransfer = balance - BigInt(Drip.fromCFX(1));
    let Cross = cfx.InternalContract('CrossSpaceCall');

    console.log(`Transferring ${new Drip(toTransfer).toCFX()} CFX from ${account.address} to ${target}...`);
    await Cross.transferEVM(target).sendTransaction({
        from: account,
        value: toTransfer,
    }).executed();

    let balance2 = await provider.getBalance(target);
    console.log(balance2);
}

main().catch((err) => console.error(err));

// console.log(format.hexAddress('cfx:aat7jbgpzx82r1baubgcpedar42g4m35k2859yeyp4'));

// let tx = Cross.transferEVM('0x1fd404ccacfd86dc20804c2610606eb06d2b3b4e');
// console.log(tx);
