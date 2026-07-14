import "VaultRebalancer"
import "EVM"

// Tear down the Rebalancer for the given EVM target: cancel its pending scheduled
// tick (refunding the fee to the deployer's FlowToken vault), then destroy the
// resource. This stops the loop and frees the derived storage path so a fresh
// setup_rebalancer can be created for the same target — and reclaims fee funds
// from an unused/misconfigured rebalancer. Debugging / operational cleanup only.
transaction(targetHex: String) {
    prepare(signer: auth(Storage) &Account) {
        let target = EVM.addressFromString(targetHex)
        let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)
        let r <- signer.storage.load<@VaultRebalancer.Rebalancer>(from: path)
            ?? panic("rebalancer not in storage at path")
        r.cancel()
        destroy r
    }
}
