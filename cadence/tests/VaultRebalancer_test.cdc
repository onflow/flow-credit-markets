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

// Failure path A: broken fee-provider cap → TickFailed emitted at schedule time.
access(all) fun testTickFailedOnInvalidFeeProvider() {
    Test.expect(_setupRebalancer(targetHex: brokenFeeTarget, coaPath: workingCoa, feeProviderPath: nonexistentVault), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: brokenFeeTarget), Test.beSucceeded())

    let failed = Test.eventsOfType(Type<VaultRebalancer.TickFailed>())
    Test.assertEqual(1, failed.length)

    let evt = failed[0] as! VaultRebalancer.TickFailed
    Test.assertEqual("fee provider capability invalid", evt.reason)
    Test.expect(evt.feeVaultBalance, Test.beNil())
}

// Failure path B: broken COA cap → schedules fine, TickFailed emitted when tick runs.
access(all) fun testTickFailedOnInvalidCoa() {
    Test.expect(_setupRebalancer(targetHex: brokenCoaTarget, coaPath: nonexistentCoa, feeProviderPath: workingFeeProvider), Test.beSucceeded())
    Test.expect(_scheduleNext(targetHex: brokenCoaTarget), Test.beSucceeded())

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    let failed = Test.eventsOfType(Type<VaultRebalancer.TickFailed>())
    Test.assertEqual(1, failed.length)

    let evt = failed[0] as! VaultRebalancer.TickFailed
    Test.assertEqual("COA capability invalid", evt.reason)
    // Fee provider works here, so balance is non-nil.
    Test.expect(evt.feeVaultBalance, Test.not(Test.beNil()))
}
