import "EVM"
import "FlowToken"
import "FungibleToken"
import "FlowTransactionScheduler"

/// A self-rescheduling Cadence resource that invokes a single EVM function at a
/// fixed interval via FLIP-330 `FlowTransactionScheduler`. The target is
/// FCMVault's `rebalance` function.
access(all) contract VaultRebalancer {

    /// Gates the setters for tickInterval, evmGasLimit, and executionEffort.
    access(all) entitlement Configure

    /// Deterministic path keyed only on `target`. Since storage is per-account, this
    /// enforces one rebalancer per (account, target): a second save at the same path
    /// aborts.
    access(all) view fun deriveRebalancerStoragePath(target: EVM.EVMAddress): StoragePath {
        return StoragePath(identifier: "vaultRebalancer_\(target.toString())")!
    }

    /// Public path for the `&Rebalancer` capability, for borrowing the permissionless
    /// `scheduleNext()`. Shares the `deriveRebalancerStoragePath` identifier so it
    /// resolves to the saved resource. Not yet published by any setup transaction.
    access(all) view fun deriveRebalancerPublicPath(target: EVM.EVMAddress): PublicPath {
        return PublicPath(identifier: "vaultRebalancer_\(target.toString())")!
    }

    /// Emitted after the EVM call, including when it reverts (a revert is reported
    /// here). `evmStatus` is the raw EVM.Status value
    /// (0 unknown, 1 invalid, 2 failed, 3 successful), so a Ticked event does not
    /// imply success; `evmErrorMessage` carries the revert reason when it didn't.
    access(all) event Ticked(
        evmStatus: UInt8,
        evmErrorCode: UInt64,
        evmErrorMessage: String,
        evmGasUsed: UInt64
    )

    /// Emitted on the initial schedule and on each self-reschedule. `id` is the
    /// scheduler handle for the outstanding tx; `nextTickAt` is the absolute
    /// timestamp it fires at, not a delay; `fee` is the FLOW paid to the scheduler
    /// for this tick.
    access(all) event Scheduled(id: UInt64, nextTickAt: UFix64, fee: UFix64)

    /// Emitted when tunable scheduling parameters are updated, by their
    /// respective setters (setTickInterval, setEvmGasLimit, setExecutionEffort).
    access(all) event TickIntervalUpdated(old: UFix64, new: UFix64)
    access(all) event EvmGasLimitUpdated(old: UInt64, new: UInt64)
    access(all) event ExecutionEffortUpdated(old: UInt64, new: UInt64)

    /// Owner-held resource, one per (account, target) by storage occupancy (see
    /// deriveRebalancerStoragePath). The owner mutates scheduling parameters via the
    /// Configure entitlement; scheduleNext is access(all) so the tick loop can be
    /// (re)started after it halts.
    access(all) resource Rebalancer: FlowTransactionScheduler.TransactionHandler {

        /// EVM contract the tick calls; also derives the storage path. These three
        /// fields are immutable: changing any requires recreating the resource (a new
        /// target lands at a new path, a calldata/priority change at the same path).
        access(all) let targetAddress: EVM.EVMAddress

        /// ABI-encoded calldata sent on each tick.
        access(all) let calldata: [UInt8]

        /// Scheduler priority for each scheduled tick.
        access(all) let priority: FlowTransactionScheduler.Priority

        /// Capability used to invoke the configured EVM call, entitled only to `EVM.Call`
        /// so it cannot otherwise act as the account owner. If it can't be borrowed at
        /// tick time, the tick reverts; the loop halts until restarted via scheduleNext.
        access(self) let coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>

        /// Caller-owned FlowToken vault the rebalancer withdraws FLOW from to pay
        /// scheduling fees. An invalid cap or insufficient balance reverts the tick;
        /// the loop halts until restarted via scheduleNext.
        access(self) let feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

        /// Capability back to this resource as the scheduler's TransactionHandler,
        /// passed to FlowTransactionScheduler.schedule() so each tick re-enters
        /// executeTransaction here. Resolved at borrow time, so it can be issued over
        /// the target path before the resource is saved there.
        access(self) let selfHandler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>

        /// Seconds between ticks.
        access(all) var tickInterval: UFix64

        /// Gas cap for the EVM call.
        access(all) var evmGasLimit: UInt64

        /// Cadence execution-effort budget for the scheduled tick.
        access(all) var executionEffort: UInt64

        /// Handle to the most recently scheduled tick, or nil if none has been
        /// scheduled. Non-nil does not imply a live tick: the handle is reaped
        /// lazily, so it may hold a finalized status (Executed/Canceled/Unknown).
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

        /// Idempotent. Schedules the next tick and emits `Scheduled` unless one is already
        /// scheduled (a no-op). A reschedule failure reverts the tick and halts the loop,
        /// surfaced only as a missing `Ticked`; restartable via a later scheduleNext.
        access(all) fun scheduleNext() {
            // Only reschedule once any prior handle has finalized.
            if self.current != nil {
                let ref = (&self.current as &FlowTransactionScheduler.ScheduledTransaction?)!
                if ref.status() == FlowTransactionScheduler.Status.Scheduled {
                    return
                }
                // Finalized (Executed/Canceled/Unknown): drop the stale handle before rescheduling.
                let stale <- self.current <- nil
                destroy stale
            }

            // calculateFee is pure arithmetic over the config values and can't abort.
            let nextTime = getCurrentBlock().timestamp + self.tickInterval
            let fee = FlowTransactionScheduler.calculateFee(
                executionEffort: self.executionEffort,
                priority: self.priority,
                dataSizeMB: 0.0
            )

            // From here any failure reverts the whole tick (unborrowable fee cap, low
            // FLOW, storage-min, bad schedule config), surfaced only as a missing Ticked.
            let vault = self.feeProvider.borrow() ?? panic("fee provider capability unborrowable")
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
        }

        /// FlowTransactionScheduler.TransactionHandler entry point, called by the
        /// scheduler at tick time. A reverting EVM call does NOT halt the loop: it
        /// emits Ticked with the EVM status and reschedules as normal. Any other
        /// failure (unborrowable COA, or a reschedule failure) reverts the whole tick
        /// with no Ticked; the loop halts until restarted via scheduleNext.
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id _id: UInt64, data _data: AnyStruct?) {
            // Drop the just-executed handle regardless of outcome.
            let executed <- self.current <- nil
            destroy executed

            // COA unborrowable reverts the tick (no Ticked); resumes via scheduleNext().
            let coaRef = self.coa.borrow() ?? panic("COA capability unborrowable")

            let result = coaRef.call(
                to: self.targetAddress,
                data: self.calldata,
                gasLimit: self.evmGasLimit,
                value: EVM.Balance(attoflow: 0)
            )

            emit Ticked(
                evmStatus: result.status.rawValue,
                evmErrorCode: result.errorCode,
                evmErrorMessage: result.errorMessage,
                evmGasUsed: result.gasUsed
            )

            self.scheduleNext()
        }

    }

    /// Creates a Rebalancer. The caller must save the result at
    /// `deriveRebalancerStoragePath(target:)` and issue `selfHandler` over that
    /// same path; otherwise the resource cannot reschedule itself. The path may
    /// be empty when the capability is issued, since it resolves at borrow time.
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
