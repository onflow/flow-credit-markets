import "VaultRebalancer"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"
import "EVM"

// Create and save a Rebalancer for the given EVM target, issuing the COA and
// fee-provider caps over the caller-supplied coaPath / feeProviderPath.
transaction(
    targetHex: String,
    coaPath: StoragePath,
    feeProviderPath: StoragePath,
    calldata: [UInt8],
    priority: UInt8,
    tickInterval: UFix64,
    evmGasLimit: UInt64,
    executionEffort: UInt64
) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        // Ensure a COA exists at /storage/evm so callers passing that as coaPath get a working capability.
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-coa, to: /storage/evm)
        }

        let target = EVM.addressFromString(targetHex)
        let storagePath = VaultRebalancer.deriveRebalancerStoragePath(target: target)

        let coaCap = signer.capabilities.storage.issue<auth(EVM.Call) &EVM.CadenceOwnedAccount>(coaPath)
        let feeProviderCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(feeProviderPath)
        let selfHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(storagePath)

        let rebalancer <- VaultRebalancer.createRebalancer(
            targetAddress: target,
            calldata: calldata,
            priority: FlowTransactionScheduler.Priority(rawValue: priority)
                ?? panic("invalid priority rawValue"),
            coa: coaCap,
            selfHandler: selfHandlerCap,
            feeProvider: feeProviderCap,
            tickInterval: tickInterval,
            evmGasLimit: evmGasLimit,
            executionEffort: executionEffort
        )
        signer.storage.save(<-rebalancer, to: storagePath)
    }
}
