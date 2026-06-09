import Test
import "test_helpers.cdc"
import "VaultRebalancer"

access(all) let admin = Test.serviceAccount()

// Deploys VaultRebalancer once before tests run.
access(all) fun setup() {
    let err = Test.deployContract(
        name: "VaultRebalancer",
        path: "../contracts/VaultRebalancer.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

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

access(all) fun testCreateRebalancer() {
    let res = _executeTransaction("../transactions/setup_rebalancer.cdc", [mainTarget, workingCoa, workingFeeProvider], admin)
    Test.expect(res, Test.beSucceeded())
}

// First scheduleNext() schedules a tick; a second call while still scheduled is a no-op.
access(all) fun testScheduleNextAndIdempotency() {
    let scheduledType = Type<VaultRebalancer.Scheduled>()
    let before = Test.eventsOfType(scheduledType).length

    Test.expect(_executeTransaction("../transactions/schedule_next.cdc", [mainTarget], admin), Test.beSucceeded())
    Test.assertEqual(before + 1, Test.eventsOfType(scheduledType).length)

    Test.expect(_executeTransaction("../transactions/schedule_next.cdc", [mainTarget], admin), Test.beSucceeded())
    Test.assertEqual(before + 1, Test.eventsOfType(scheduledType).length)
}

// Advancing time fires the tick (Ticked) and the handler re-arms itself (Scheduled).
access(all) fun testTickFiresAndSelfReschedules() {
    let tickedType = Type<VaultRebalancer.Ticked>()
    let scheduledType = Type<VaultRebalancer.Scheduled>()
    let tickedBefore = Test.eventsOfType(tickedType).length
    let scheduledBefore = Test.eventsOfType(scheduledType).length

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    Test.assertEqual(tickedBefore + 1, Test.eventsOfType(tickedType).length)
    Test.assertEqual(scheduledBefore + 1, Test.eventsOfType(scheduledType).length)

    // Empty calldata to the ecrecover precompile (0x...01) returns success, so evmErrorCode == 0.
    let allTicked = Test.eventsOfType(tickedType)
    let latest = allTicked[allTicked.length - 1] as! VaultRebalancer.Ticked
    Test.expect(latest.evmErrorCode, Test.equal(0 as UInt64))
}

// Advance time a second time; another tick must fire, showing the self-reschedule loop persists across ticks.
access(all) fun testLoopContinues() {
    let tickedBefore = Test.eventsOfType(Type<VaultRebalancer.Ticked>()).length
    let scheduledBefore = Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    Test.assertEqual(tickedBefore + 1, Test.eventsOfType(Type<VaultRebalancer.Ticked>()).length)
    Test.assertEqual(scheduledBefore + 1, Test.eventsOfType(Type<VaultRebalancer.Scheduled>()).length)
}

// setTickInterval emits TickIntervalUpdated and the new value persists.
access(all) fun testSetTickIntervalPersistsAndEmits() {
    let evtType = Type<VaultRebalancer.TickIntervalUpdated>()
    let before = Test.eventsOfType(evtType).length
    Test.expect(_executeTransaction("../transactions/set_tick_interval.cdc", [mainTarget, 20.0], admin), Test.beSucceeded())
    Test.assertEqual(before + 1, Test.eventsOfType(evtType).length)

    let result = Test.executeScript(
        Test.readFile("../scripts/get_tick_interval.cdc"),
        [admin.address, mainTarget]
    )
    Test.expect(result, Test.beSucceeded())
    Test.assertEqual(20.0, result.returnValue! as! UFix64)
}

// Failure path A: broken fee-provider cap → TickFailed emitted at schedule time.
access(all) fun testTickFailedOnInvalidFeeProvider() {
    let failedType = Type<VaultRebalancer.TickFailed>()
    let before = Test.eventsOfType(failedType).length

    Test.expect(_executeTransaction("../transactions/setup_rebalancer.cdc", [brokenFeeTarget, workingCoa, nonexistentVault], admin), Test.beSucceeded())
    Test.expect(_executeTransaction("../transactions/schedule_next.cdc", [brokenFeeTarget], admin), Test.beSucceeded())

    let failed = Test.eventsOfType(failedType)
    Test.assertEqual(before + 1, failed.length)

    let evt = failed[failed.length - 1] as! VaultRebalancer.TickFailed
    Test.assertEqual("fee provider capability invalid", evt.reason)
    Test.expect(evt.feeVaultBalance, Test.beNil())
}

// Failure path B: broken COA cap → schedules fine, TickFailed emitted when tick runs.
access(all) fun testTickFailedOnInvalidCoa() {
    let failedType = Type<VaultRebalancer.TickFailed>()
    let before = Test.eventsOfType(failedType).length

    Test.expect(_executeTransaction("../transactions/setup_rebalancer.cdc", [brokenCoaTarget, nonexistentCoa, workingFeeProvider], admin), Test.beSucceeded())
    Test.expect(_executeTransaction("../transactions/schedule_next.cdc", [brokenCoaTarget], admin), Test.beSucceeded())

    Test.moveTime(by: 15.0)
    Test.commitBlock()

    let failed = Test.eventsOfType(failedType)
    Test.assertEqual(before + 1, failed.length)

    let evt = failed[failed.length - 1] as! VaultRebalancer.TickFailed
    Test.assertEqual("COA capability invalid", evt.reason)
    // Fee provider works here, so balance is non-nil.
    Test.expect(evt.feeVaultBalance, Test.not(Test.beNil()))
}
