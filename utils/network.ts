import "dotenv/config";

export function getMnemonic(networkName?: string): string {
	if (networkName) {
		const mnemonic = process.env["MNEMONIC_" + networkName.toUpperCase()];
		if (mnemonic && mnemonic !== "") {
			return mnemonic;
		}
	}

	const mnemonic = process.env.MNEMONIC;
	if (!mnemonic || mnemonic === "") {
		return "test test test test test test test test test test test junk";
	}
	return mnemonic;
}

export function accounts(networkName?: string): { mnemonic: string } {
	return { mnemonic: getMnemonic(networkName) };
}