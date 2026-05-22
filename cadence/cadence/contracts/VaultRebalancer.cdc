import "EVM"
import "FlowToken"
import "FungibleToken"
import "FlowTransactionScheduler"

/// VaultRebalancer — a self-rescheduling Cadence resource that invokes a single
/// EVM function (`rebalance()`) at a fixed interval via FLIP-330
/// `FlowTransactionScheduler`.
access(all) contract VaultRebalancer {

    /// Entitlement for calibration mutation.
    access(all) entitlement Configure

    /// Storage path derived from the EVM target. Storage occupancy enforces
    /// one rebalancer per (account, target).
    access(all) view fun deriveRebalancerStoragePath(target: EVM.EVMAddress): StoragePath {
        return StoragePath(identifier: "vaultRebalancer_\(target.toString())")!
    }

    /// Public path for the `&Rebalancer` capability used by the permissionless
    /// `scheduleNext` entry.
    access(all) view fun deriveRebalancerPublicPath(target: EVM.EVMAddress): PublicPath {
        return PublicPath(identifier: "vaultRebalancer_\(target.toString())")!
    }

    /// Events

    /// Emitted on each tick with the EVM call outcome.
    access(all) event Ticked(
        evmStatus: UInt8,
        evmErrorCode: UInt64,
        evmGasUsed: UInt64
    )

    /// Emitted when a tick can't progress — either self-rescheduling failed, or
    /// the EVM call couldn't be made (e.g., COA cap invalid). The loop halts
    /// until a permissionless `scheduleNext` call restarts it.
    /// `feeVaultBalance` is nil when the fee-provider cap can't be borrowed.
    access(all) event TickFailed(reason: String, feeVaultBalance: UFix64?)

    /// Emitted when a tick is scheduled (initial or self-reschedule).
    access(all) event Scheduled(id: UInt64, nextTickAt: UFix64, fee: UFix64)

    /// Emitted on per-field calibration changes via the Configure entitlement.
    access(all) event TickIntervalUpdated(old: UFix64, new: UFix64)
    access(all) event EvmGasLimitUpdated(old: UInt64, new: UInt64)
    access(all) event ExecutionEffortUpdated(old: UInt64, new: UInt64)

    /// The Rebalancer resource. One per (account, target). Admin-owned.
    access(all) resource Rebalancer: FlowTransactionScheduler.TransactionHandler {

        /// Identity — the commitment. Immutable. Changing any of these requires
        /// destroy + recreate (a new resource at a different deterministic path).
        access(all) let targetAddress: EVM.EVMAddress
        access(all) let calldata: [UInt8]
        access(all) let priority: FlowTransactionScheduler.Priority

        /// Capability to the COA — `auth(EVM.Call)` only.
        access(self) let coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>

        /// Withdraw-entitled capability to a FlowToken vault. Caller decides where
        /// the vault lives and how it's funded; the rebalancer just pulls FLOW
        /// when paying scheduling fees.
        access(self) let feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

        /// Self-capability for FlowTransactionScheduler.schedule(). Capabilities
        /// resolve at borrow time, so the target path can be empty when this is
        /// issued — letting us pass it into the constructor before the resource
        /// is saved.
        access(self) let selfHandler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>

        /// Calibration — mutable via the `Configure` entitlement. Each field
        /// drifts from an independent external force (Solidity gas profile,
        /// Cadence governance weights, scheduler contention) and is tuned
        /// independently. New values take effect on the next `scheduleNext`;
        /// any tick already scheduled fires with its existing parameters.
        access(all) var tickInterval: UFix64
        access(all) var evmGasLimit: UInt64
        access(all) var executionEffort: UInt64

        /// Current outstanding scheduled-tx handle, if any.
        access(self) var current: @FlowTransactionScheduler.ScheduledTransaction?

        init(
            targetAddress: EVM.EVMAddress,
            calldata: [UInt8],
            priority: FlowTransactionScheduler.Priority,
            coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>,
            selfHandler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            tickInterval: UFix64,
            evmGasLimit: UInt64,
            executionEffort: UInt64
        ) {
            pre {
                tickInterval > 0.0: "tickInterval must be positive"
                executionEffort > 0: "executionEffort must be positive"
                evmGasLimit > 0: "evmGasLimit must be positive"
            }
            self.targetAddress = targetAddress
            self.calldata = calldata
            self.priority = priority
            self.coa = coa
            self.selfHandler = selfHandler
            self.feeProvider = feeProvider
            self.tickInterval = tickInterval
            self.evmGasLimit = evmGasLimit
            self.executionEffort = executionEffort
            self.current <- nil
        }

        access(Configure) fun setTickInterval(_ v: UFix64) {
            pre { v > 0.0: "tickInterval must be positive" }
            emit TickIntervalUpdated(old: self.tickInterval, new: v)
            self.tickInterval = v
        }

        access(Configure) fun setEvmGasLimit(_ v: UInt64) {
            pre { v > 0: "evmGasLimit must be positive" }
            emit EvmGasLimitUpdated(old: self.evmGasLimit, new: v)
            self.evmGasLimit = v
        }

        access(Configure) fun setExecutionEffort(_ v: UInt64) {
            pre { v > 0: "executionEffort must be positive" }
            emit ExecutionEffortUpdated(old: self.executionEffort, new: v)
            self.executionEffort = v
        }

        /// Permissionless idempotent scheduling. Ensures a tick is scheduled.
        /// Returns true if a new tick was scheduled; false otherwise. The two
        /// "false" cases (already alive — no-op; or rescheduling failed) are
        /// distinguishable via events: `TickFailed` is emitted on failure,
        /// nothing is emitted on no-op.
        access(all) fun scheduleNext(): Bool {
            // If we hold a scheduled-tx handle, check its status.
            if self.current != nil {
                let ref = (&self.current as &FlowTransactionScheduler.ScheduledTransaction?)!
                if ref.status() == FlowTransactionScheduler.Status.Scheduled {
                    // Already alive — no-op.
                    return false
                }
                // Finalized (Executed/Canceled/Unknown) — drop the stale handle.
                let stale <- self.current <- nil
                destroy stale
            }

            // calculateFee is the cheap path; we control the args that would make
            // schedule() panic (handler cap, effort range, future timestamp).
            let nextTime = getCurrentBlock().timestamp + self.tickInterval
            let fee = FlowTransactionScheduler.calculateFee(
                executionEffort: self.executionEffort,
                priority: self.priority,
                dataSizeMB: 0.0
            )

            // Borrow the fee provider; if the capability is invalid the loop can't pay fees.
            guard let vault = self.feeProvider.borrow() else {
                emit TickFailed(
                    reason: "fee provider capability invalid",
                    feeVaultBalance: nil
                )
                return false
            }

            if vault.balance < fee {
                emit TickFailed(
                    reason: "insufficient FLOW (need \(fee))",
                    feeVaultBalance: vault.balance
                )
                return false
            }

            let payment <- vault.withdraw(amount: fee) as! @FlowToken.Vault
            let scheduled <- FlowTransactionScheduler.schedule(
                handlerCap: self.selfHandler,
                data: nil,
                timestamp: nextTime,
                priority: self.priority,
                executionEffort: self.executionEffort,
                fees: <-payment
            )
            let scheduledId = scheduled.id

            let stale <- self.current <- scheduled
            destroy stale

            emit Scheduled(id: scheduledId, nextTickAt: nextTime, fee: fee)
            return true
        }

        /// FlowTransactionScheduler.TransactionHandler entry point. Called by the
        /// scheduler at tick time. Performs the EVM call and self-reschedules.
        /// Failure paths emit + return rather than panic; the loop halts and is
        /// resumed by a permissionless `scheduleNext` call.
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id _id: UInt64, data _data: AnyStruct?) {
            // Drop the just-executed handle regardless of outcome.
            let executed <- self.current <- nil
            destroy executed

            // COA cap unborrowable: halt without rescheduling to avoid burning
            // fees on a guaranteed-failing call. Resumes via scheduleNext().
            guard let coaRef = self.coa.borrow() else {
                emit TickFailed(
                    reason: "COA capability invalid",
                    feeVaultBalance: self.feeProvider.borrow()?.balance
                )
                return
            }

            let result = coaRef.call(
                to: self.targetAddress,
                data: self.calldata,
                gasLimit: self.evmGasLimit,
                value: EVM.Balance(attoflow: 0)
            )

            emit Ticked(
                evmStatus: result.status.rawValue,
                evmErrorCode: result.errorCode,
                evmGasUsed: result.gasUsed
            )

            let _ = self.scheduleNext()
        }

    }

    /// Factory: create a new Rebalancer.
    /// Caller is expected to issue the `selfHandler` capability over the target
    /// storage path before constructing (the path may be empty at that point —
    /// capabilities resolve at borrow time, not at issue time). Save the
    /// resulting resource at `deriveRebalancerStoragePath(target:)`.
    access(all) fun createRebalancer(
        targetAddress: EVM.EVMAddress,
        calldata: [UInt8],
        priority: FlowTransactionScheduler.Priority,
        coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>,
        selfHandler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
        tickInterval: UFix64,
        evmGasLimit: UInt64,
        executionEffort: UInt64
    ): @Rebalancer {
        return <- create Rebalancer(
            targetAddress: targetAddress,
            calldata: calldata,
            priority: priority,
            coa: coa,
            selfHandler: selfHandler,
            feeProvider: feeProvider,
            tickInterval: tickInterval,
            evmGasLimit: evmGasLimit,
            executionEffort: executionEffort,
        )
    }

}
