import "VaultRebalancer"
import "EVM"

// Cancel the pending scheduled tick for the given EVM target's Rebalancer
// (refunding the fee to the deployer's FlowToken vault), then put the resource
// back in storage. Unlike remove_rebalancer, this preserves the Rebalancer so it
// can be re-armed later — it just halts the loop. Debugging / operational use only.
transaction(targetHex: String) {
    prepare(signer: auth(Storage) &Account) {
        let target = EVM.addressFromString(targetHex)
        let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)
        let r <- signer.storage.load<@VaultRebalancer.Rebalancer>(from: path)
            ?? panic("rebalancer not in storage at path")
        r.cancel()
        signer.storage.save(<-r, to: path)
    }
}
