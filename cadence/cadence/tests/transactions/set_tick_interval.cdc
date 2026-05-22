import "VaultRebalancer"
import "EVM"

// Bump the tickInterval on the rebalancer at the path derived from `targetHex`.
transaction(targetHex: String, newTickInterval: UFix64) {
    prepare(signer: auth(Storage) &Account) {
        let target = EVM.addressFromString(targetHex)
        let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)
        let r = signer.storage.borrow<auth(VaultRebalancer.Configure) &VaultRebalancer.Rebalancer>(from: path)
            ?? panic("rebalancer not in storage")
        r.setTickInterval(newTickInterval)
    }
}
