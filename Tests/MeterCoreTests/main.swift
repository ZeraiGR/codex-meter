import Foundation
import MeterCore

private var failures = 0
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() != rhs() { failures += 1; print("FAIL equality at \(file):\(line)") } }
    catch { failures += 1; print("FAIL \(error) at \(file):\(line)") }
}
func XCTAssertEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(abs(lhs-rhs)<=accuracy, file:file,line:line) }
func XCTAssertNotEqual<T:Equatable>(_ lhs:T,_ rhs:T,file:StaticString = #filePath,line:UInt = #line){XCTAssertTrue(lhs != rhs,file:file,line:line)}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(try value(),true,file:file,line:line) }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(try value(),false,file:file,line:line) }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try value() == nil,file:file,line:line) }
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try value() != nil,file:file,line:line) }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try value(); failures += 1; print("FAIL expected error at \(file):\(line)") } catch {} }
func XCTUnwrap<T>(_ value:T?) throws -> T { guard let value else{throw MeterError("Expected non-null value")};return value }

let suite = MeterCoreTests()
let checks: [(String, () throws -> Void)] = [
    ("testTaskSortingUsesNumbersAndKeepsUnknownCostsLast", suite.testTaskSortingUsesNumbersAndKeepsUnknownCostsLast),
    ("testTaskFiltersCombineStatusKindAndWordsWithoutLosingSelectionIdentity", suite.testTaskFiltersCombineStatusKindAndWordsWithoutLosingSelectionIdentity),
    ("testTaskSortingUsesSummedMeasuredCostAndStableTies", suite.testTaskSortingUsesSummedMeasuredCostAndStableTies),
    ("testWeeklyQuotaDoesNotDependOnPaymentAndMarksPartialCoverage", suite.testWeeklyQuotaDoesNotDependOnPaymentAndMarksPartialCoverage),
    ("testWeeklyQuotaSumsAcrossResetsWithoutCappingAt100", suite.testWeeklyQuotaSumsAcrossResetsWithoutCappingAt100),
    ("testWeeklyQuotaRejectsShortWindowsAndMixedAccounts", suite.testWeeklyQuotaRejectsShortWindowsAndMixedAccounts),
    ("testWeeklyQuotaSurvivesDatabaseAndCLIWithoutChangingFullQuotaContract", suite.testWeeklyQuotaSurvivesDatabaseAndCLIWithoutChangingFullQuotaContract),

    ("testFirstPaymentDraftStartsTodayWithoutCopyingMoney", suite.testFirstPaymentDraftStartsTodayWithoutCopyingMoney),
    ("testPaymentDraftUsesLatestEndRegardlessOfOrderOrToday", suite.testPaymentDraftUsesLatestEndRegardlessOfOrderOrToday),
    ("testMultiMonthPaymentDraftSuggestsOnlyOneFollowingMonth", suite.testMultiMonthPaymentDraftSuggestsOnlyOneFollowingMonth),
    ("testPaymentDraftHandlesShortMonthsAndLeapYearsWithoutDayDrift", suite.testPaymentDraftHandlesShortMonthsAndLeapYearsWithoutDayDrift),

    ("testQuotaTimeUsesResetWindowAndAdvancesWithoutQuotaChanges", suite.testQuotaTimeUsesResetWindowAndAdvancesWithoutQuotaChanges),
    ("testQuotaTimeDoesNotInventMissingOrExpiredWindows", suite.testQuotaTimeDoesNotInventMissingOrExpiredWindows),
    ("testProjectedTaskCostUsesUnroundedCoverageAndIncludesMeasuredPart", suite.testProjectedTaskCostUsesUnroundedCoverageAndIncludesMeasuredPart),
    ("testProjectedTaskCostRejectsMissingAndInvalidInputs", suite.testProjectedTaskCostRejectsMissingAndInvalidInputs),
    ("testPartialCostIsPreservedWithoutPretendingToBeTotal", suite.testPartialCostIsPreservedWithoutPretendingToBeTotal),
    ("testCostSumsAllRunsAndPreservesUnassignedShare", suite.testCostSumsAllRunsAndPreservesUnassignedShare),
    ("testPartialPaymentDoesNotClaimFullCostCoverage", suite.testPartialPaymentDoesNotClaimFullCostCoverage),
    ("testZeroQuotaAndMixedAccountsDoNotProducePartialPrice", suite.testZeroQuotaAndMixedAccountsDoNotProducePartialPrice),
    ("testTaskSummaryKeepsMeasuredCostFromDatabase", suite.testTaskSummaryKeepsMeasuredCostFromDatabase),

    ("testTranscriptCanonicalMessagesAndTurnBoundaries", suite.testTranscriptCanonicalMessagesAndTurnBoundaries),
    ("testTranscriptExcludesInternalRolesAndReasoning", suite.testTranscriptExcludesInternalRolesAndReasoning),
    ("testTranscriptLegacyAndDuplicateStreams", suite.testTranscriptLegacyAndDuplicateStreams),
    ("testServiceRunsKeepCountersWithoutInternalTranscript", suite.testServiceRunsKeepCountersWithoutInternalTranscript),
    ("testOldRunRecordsDecodeWithoutTranscriptMetadata", suite.testOldRunRecordsDecodeWithoutTranscriptMetadata),
    ("testTranscriptBackfillPreservesBindingsAndCounters", suite.testTranscriptBackfillPreservesBindingsAndCounters),
    ("testFullTimeIncludesPauseBeforeTaskCompletion", suite.testFullTimeIncludesPauseBeforeTaskCompletion),
    ("testResetTimestampJitterPreservesNotificationIdentity", suite.testResetTimestampJitterPreservesNotificationIdentity),
    ("testPriceFromActualPayment", suite.testPriceFromActualPayment),
    ("testAvailableSeparatesFutureResets", suite.testAvailableSeparatesFutureResets),
    ("testPaymentOverlapAndMissingPeriod", suite.testPaymentOverlapAndMissingPeriod),
    ("testPartialBillingWindowDoesNotExceedPayment", suite.testPartialBillingWindowDoesNotExceedPayment),
    ("testCachedAndReasoningNotDoubleCounted", suite.testCachedAndReasoningNotDoubleCounted),
    ("testParallelTimeIsUnion", suite.testParallelTimeIsUnion),
    ("testJournalDeduplicatesCountersAndIgnoresPartialLine", suite.testJournalDeduplicatesCountersAndIgnoresPartialLine),
    ("testTaskSpansTurnsAndEndDoesNotLoseFinalTokens", suite.testTaskSpansTurnsAndEndDoesNotLoseFinalTokens),
    ("testMergeAndUnassignedResources", suite.testMergeAndUnassignedResources),
    ("testWarningsAt50AndNoDuplicates", suite.testWarningsAt50AndNoDuplicates),
    ("testExpiryReminderAt35PercentTwoDaysAndOneDay", suite.testExpiryReminderAt35PercentTwoDaysAndOneDay),
    ("testAttributionDoesNotAddDifferentWindowsOrCrossReset", suite.testAttributionDoesNotAddDifferentWindowsOrCrossReset),
    ("testAttributionReservesUnassignedShare", suite.testAttributionReservesUnassignedShare),
    ("testAttributionMissingSnapshotsDoesNotPretendTotal", suite.testAttributionMissingSnapshotsDoesNotPretendTotal),
    ("testForecastRefusesUnfoundedConfidence", suite.testForecastRefusesUnfoundedConfidence),
    ("testTaskCLIReusesAndPausesCorrectly", suite.testTaskCLIReusesAndPausesCorrectly),
    ("testHookProvidesTaskContextWithoutNetwork", suite.testHookProvidesTaskContextWithoutNetwork)
]
for (name, check) in checks {
    let before=failures
    do {try check()} catch {failures += 1;print("FAIL \(name): \(error)")}
    if failures==before {print("PASS \(name)")}
}
do {try await suite.testTranscriptSearchReadsAnswersAndInvalidatesCache();print("PASS testTranscriptSearchReadsAnswersAndInvalidatesCache")} catch {failures += 1;print("FAIL transcript search: \(error)")}
print("\(checks.count+1) checks; \(failures) failures")
exit(failures == 0 ? 0 : 1)
