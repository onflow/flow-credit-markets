import "VaultRebalancer"
import "EVM"

access(all) fun main(addr: Address, targetHex: String): UFix64 {
    let target = EVM.addressFromString(targetHex)
    let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)
    let r = getAuthAccount<auth(BorrowValue) &Account>(addr)
        .storage.borrow<&VaultRebalancer.Rebalancer>(from: path)
        ?? panic("rebalancer not in storage")
    return r.tickInterval
}
