import Test

// Build + run a tx, return the result.
access(all) fun _executeTransaction(
    _ path: String,
    _ args: [AnyStruct],
    _ signer: Test.TestAccount
): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    )
    return Test.executeTransaction(txn)
}
