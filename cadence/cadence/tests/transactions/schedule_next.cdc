import "VaultRebalancer"
import "EVM"

transaction(targetHex: String) {
    prepare(signer: auth(Storage) &Account) {
        let target = EVM.addressFromString(targetHex)
        let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)
        let r = signer.storage.borrow<&VaultRebalancer.Rebalancer>(from: path)
            ?? panic("rebalancer not in storage at path")
        let _ = r.scheduleNext()
    }
}
