import Test
import BlockchainHelpers
import "test_helpers.cdc"
import "VaultRebalancer"
import "FlowTransactionScheduler"

access(all) let admin = Test.serviceAccount()

// Post-deploy height; each test resets here to stay self-contained.
access(all) var snapshot: UInt64 = 0

// Distinct EVM targets → distinct storage paths via deriveRebalancerStoragePath.
access(all) let mainTarget = "0x0000000000000000000000000000000000000001"
access(all) let brokenFeeTarget = "0x0000000000000000000000000000000000000002"
access(all) let brokenCoaTarget = "0x0000000000000000000000000000000000000003"

// The nonexistent paths are empty, so caps issued against them return nil on
// borrow; the failure tests below use them to exercise the halt branches.
access(all) let workingCoa = /storage/evm
access(all) let workingFeeProvider = /storage/flowTokenVault
access(all) let nonexistentCoa = /storage/noCoaHere
access(all) let nonexistentVault = /storage/noVaultHere

// Deploys VaultRebalancer once before tests run.
access(all) fun setup() {
    let err = Test.deployContract(
        name: "VaultRebalancer",
        path: "../contracts/VaultRebalancer.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    snapshot = getCurrentBlockHeight()
}

access(all) fun beforeEach() {
    Test.reset(to: snapshot)
}

// Creates a Rebalancer for `targetHex` with the test settings hard-coded.
access(all) fun _setupRebalancer(
    targetHex: String,
    coaPath: StoragePath,
    feeProviderPath: StoragePath
): Test.TransactionResult {
    return _executeTransaction(
        "../transactions/setup_rebalancer.cdc",
        [
            targetHex,
            coaPath,
            feeProviderPath,
            [] as [UInt8], // calldata
            FlowTransactionScheduler.Priority.Medium.rawValue, // priority
            10.0 as UFix64, // tickInterval
            200_000 as UInt64, // evmGasLimit
            5_000 as UInt64 // executionEffort
        ],
        admin
    )
}

access(all) fun _scheduleNext(targetHex: String): Test.TransactionResult {
    return _executeTransaction("../transactions/schedule_next.cdc", [targetHex], admin)
}

access(all) fun _getTickInterval(targetHex: String): Test.ScriptResult {
    return _executeScript("../scripts/get_tick_interval.cdc", [admin.address, targetHex])
}

access(all) fun _setTickInterval(targetHex: String, newInterval: UFix64): Test.TransactionResult {
    return _executeTransaction("../transactions/set_tick_interval.cdc", [targetHex, newInterval], admin)
}

// Full teardown: cancel the pending tick (refunding its fee) and destroy the resource.
access(all) fun _removeRebalancer(targetHex: String): Test.TransactionResult {
    return _executeTransaction("../transactions/remove_rebalancer.cdc", [targetHex], admin)
}

// Cancel-only: load the rebalancer, call cancel(), and put it back — exercises
// cancel() in isolation (no destroy), so the resource stays usable afterward.
access(all) fun _cancelRebalancer(targetHex: String): Test.TransactionResult {
    let code = "import \"VaultRebalancer\"\n"
        .concat("import \"EVM\"\n")
        .concat("transaction(targetHex: String) {\n")
        .concat("  prepare(signer: auth(Storage) &Account) {\n")
        .concat("    let target = EVM.addressFromString(targetHex)\n")
        .concat("    let path = VaultRebalancer.deriveRebalancerStoragePath(target: target)\n")
        .concat("    let r <- signer.storage.load<@VaultRebalancer.Rebalancer>(from: path)\n")
        .concat("      ?? panic(\"rebalancer not in storage\")\n")
        .concat("    r.cancel()\n")
        .concat("    signer.storage.save(<-r, to: path)\n")
        .concat("  }\n")
        .concat("}")
    return Test.executeTransaction(Test.Transaction(
        code: code,
        authorizers: [admin.address],
        signers: [admin],
        arguments: [targetHex]
    ))
}

access(all) fun testCreateRebalancer() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
}

// First scheduleNext() schedules a tick; a second call while still scheduled is a no-op.
access(all) fun testScheduleNextAndIdempotency() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    let scheduledType = Type<VaultRebalancer.Scheduled>()

    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(scheduledType).length)

    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(scheduledType).length)
}

// Advancing time fires the tick (Ticked) and the handler re-arms itself (Scheduled).
access(all) fun testTickFiresAndSelfReschedules() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    let tickedType = Type<VaultRebalancer.Ticked>()
    Test.assertEqual(1, Test.eventsOfType(tickedType).length)
    Test.assertEqual(2, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)

    // Empty calldata to the ecrecover precompile (0x...01) returns success, so evmErrorCode == 0.
    let allTicked = Test.eventsOfType(tickedType)
    let latest = allTicked[allTicked.length - 1] as! VaultRebalancer.Ticked
    Test.expect(latest.evmErrorCode, Test.equal(0 as UInt64))
}

// Advance time a second time; another tick must fire, showing the self-reschedule loop persists across ticks.
access(all) fun testLoopContinues() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())

    Test.moveTime(by: 15.0)
    Test.commitBlock()
    Test.moveTime(by: 15.0)
    Test.commitBlock()

    Test.assertEqual(2, Test.eventsOfType(Type<VaultRebalancer.Ticked>()).length)
    Test.assertEqual(3, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)
}

// setTickInterval emits TickIntervalUpdated and the new value persists.
access(all) fun testSetTickIntervalPersistsAndEmits() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())

    Test.expect(_setTickInterval(targetHex: mainTarget, newInterval: 20.0), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<VaultRebalancer.TickIntervalUpdated>()).length)

    let result = _getTickInterval(targetHex: mainTarget)
    Test.expect(result, Test.beSucceeded())
    Test.assertEqual(20.0, result.returnValue! as! UFix64)
}

// A broken fee-provider cap can't be borrowed, so scheduleNext panics and the
// whole tick reverts; nothing is scheduled, surfaced as the absence of Ticked.
access(all) fun testHaltsOnInvalidFeeProvider() {
    Test.expect(_setupRebalancer(targetHex: brokenFeeTarget, coaPath: workingCoa, feeProviderPath: nonexistentVault), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: brokenFeeTarget), Test.beFailed())

    Test.assertEqual(0, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)
}

// A broken COA cap still schedules fine, but when the tick fires the handler
// can't borrow the COA, so it returns before the EVM call: no Ticked, and the
// loop stops (no reschedule).
access(all) fun testHaltsOnInvalidCoa() {
    Test.expect(_setupRebalancer(targetHex: brokenCoaTarget, coaPath: nonexistentCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: brokenCoaTarget), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    Test.assertEqual(0, Test.eventsOfType(Type<VaultRebalancer.Ticked>()).length)
    Test.assertEqual(1, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)
}

// cancel() cancels the live scheduled tick — the scheduler emits Canceled and (via
// FlowTransactionScheduler.cancel) refunds the fee into the deployer's FlowToken vault
// — while leaving the resource itself in place. (The refund magnitude depends on the
// scheduler's refundMultiplier and is exercised end-to-end in the mainnet-fork rehearsal;
// the emulator used by `flow test` refunds nothing, so balance isn't asserted here.)
access(all) fun testCancelCancelsScheduledTick() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)

    Test.expect(_cancelRebalancer(targetHex: mainTarget), Test.beSucceeded())

    // The scheduler recorded the cancellation, and the resource is untouched / readable.
    Test.assertEqual(1, Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>()).length)
    Test.expect(_getTickInterval(targetHex: mainTarget), Test.beSucceeded())
}

// After cancel() the pending tick never fires, and because `current` is cleared the
// permissionless scheduleNext() can re-arm the loop.
access(all) fun testCancelStopsLoopButAllowsResume() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())
    Test.expect(_cancelRebalancer(targetHex: mainTarget), Test.beSucceeded())

    // Past the original tick time: nothing fires, because the tick was canceled.
    Test.moveTime(by: 15.0)
    Test.commitBlock()
    Test.assertEqual(0, Test.eventsOfType(Type<VaultRebalancer.Ticked>()).length)

    // current was cleared, so the loop can be restarted (a second Scheduled is emitted).
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(2, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)
}

// cancel() is a no-op when nothing is scheduled: it succeeds, emits no Canceled, and
// leaves the resource intact.
access(all) fun testCancelNoOpWhenNothingScheduled() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())

    Test.expect(_cancelRebalancer(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(0, Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>()).length)
    Test.expect(_getTickInterval(targetHex: mainTarget), Test.beSucceeded())
}

// remove_rebalancer cancels the pending tick and destroys the resource, freeing the
// storage path so the same target can be set up again.
access(all) fun testRemoveCancelsAndFreesPath() {
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: mainTarget), Test.beSucceeded())

    Test.expect(_removeRebalancer(targetHex: mainTarget), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>()).length)

    // The resource is gone: reading its tickInterval now fails.
    Test.expect(_getTickInterval(targetHex: mainTarget), Test.beFailed())
    // The path is free: a fresh setup at the same target succeeds.
    Test.expect(_setupRebalancer(targetHex: mainTarget, coaPath: workingCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
}
