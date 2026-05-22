import "VaultRebalancer"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"
import "EVM"

// Create and save a Rebalancer for the given EVM target. Capabilities are
// issued against the caller-supplied paths (working or deliberately nonexistent)
// — the tx doesn't care which.
transaction(
    targetHex: String,
    coaPath: StoragePath,
    feeProviderPath: StoragePath
) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        // Ensure a COA exists at /storage/evm so callers passing that as coaPath
        // get a working capability. Callers wanting a broken cap pass a path
        // where no COA is saved.
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
            calldata: [],
            priority: FlowTransactionScheduler.Priority.Medium,
            coa: coaCap,
            selfHandler: selfHandlerCap,
            feeProvider: feeProviderCap,
            tickInterval: 10.0,
            evmGasLimit: 200_000,
            executionEffort: 5_000
        )
        signer.storage.save(<-rebalancer, to: storagePath)
    }
}
