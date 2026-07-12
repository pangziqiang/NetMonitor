import Testing
import Foundation
@testable import NetMonitorCore

@Suite("ProcessMonitor Tests")
struct ProcessMonitorTests {

    // MARK: - parseNettopOutput

    @Test("parseNettopOutput with valid CSV lines")
    func parseNettopValidLines() {
        let output = """
        command,pid,rx_bytes,tx_bytes
        Safari.12345,12345,1000,500
        Chrome.67890,67890,2000,300
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 2)
        #expect(result[12345]?.download == 1000)
        #expect(result[12345]?.upload == 500)
        #expect(result[67890]?.download == 2000)
        #expect(result[67890]?.upload == 300)
    }

    @Test("parseNettopOutput skips comment lines")
    func parseNettopSkipsComments() {
        let output = """
        # time,interface,state
        # blah blah
        command,pid,rx_bytes,tx_bytes
        Safari.12345,12345,1000,500
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[12345]?.download == 1000)
    }

    @Test("parseNettopOutput skips lines with fewer than 3 columns")
    func parseNettopSkipsShortLines() {
        let output = """
        command,pid,rx_bytes,tx_bytes
        Safari.12345,12345,1000
        Chrome.67890,67890,2000,300
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[67890] != nil)
    }

    @Test("parseNettopOutput handles empty input")
    func parseNettopEmpty() {
        let result = ProcessMonitor.parseNettopOutput("")
        #expect(result.isEmpty)
    }

    @Test("parseNettopOutput handles comment-only input")
    func parseNettopCommentsOnly() {
        let output = """
        # line 1
        # line 2
        # line 3
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.isEmpty)
    }

    @Test("parseNettopOutput skips lines with invalid PID")
    func parseNettopInvalidPID() {
        let output = """
        command,pid,rx_bytes,tx_bytes
        Safari.notapid,notapid,1000,500
        Chrome.67890,67890,2000,300
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[67890] != nil)
    }

    @Test("parseNettopOutput skips lines with invalid byte counts")
    func parseNettopInvalidBytes() {
        let output = """
        command,pid,rx_bytes,tx_bytes
        Safari.12345,12345,notanumber,500
        Chrome.67890,67890,2000,300
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[67890] != nil)
    }

    @Test("parseNettopOutput handles process name with dots")
    func parseNettopNameWithDots() {
        // "com.apple.Safari.12345" — split by "." gives last element as PID
        let output = "command,pid,rx_bytes,tx_bytes\ncom.apple.Safari.12345,12345,1000,500"
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[12345]?.download == 1000)
    }

    @Test("parseNettopOutput handles zero byte counts")
    func parseNettopZeroBytes() {
        let output = "command,pid,rx_bytes,tx_bytes\nSafari.12345,12345,0,0"
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[12345]?.download == 0)
        #expect(result[12345]?.upload == 0)
    }

    @Test("parseNettopOutput handles large byte counts")
    func parseNettopLargeBytes() {
        let output = "command,pid,rx_bytes,tx_bytes\nSafari.12345,12345,18446744073709551615,18446744073709551615"
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 1)
        #expect(result[12345]?.download == UInt64.max)
        #expect(result[12345]?.upload == UInt64.max)
    }

    @Test("parseNettopOutput handles macOS Sequoia format (bytes_in/bytes_out, unnamed cmd col)")
    func parseNettopSequoiaFormat() {
        // nettop -P -L 1 -n output on macOS Sequoia:
        // time,<empty>,interface,state,bytes_in,bytes_out,rx_dupe,...
        // timestamp,process.pid,,,,bytes_in,bytes_out,...
        let output = """
        time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
        20:28:33.450194,apsd.135,,,27933,71061,0,0,0,,,,,,,,,,,,
        20:28:33.450202,WeChat.9179,,,46517,28330,0,0,0,,,,,,,,,,,,
        """
        let result = ProcessMonitor.parseNettopOutput(output)
        #expect(result.count == 2)
        #expect(result[135]?.download == 27933)
        #expect(result[135]?.upload == 71061)
        #expect(result[9179]?.download == 46517)
        #expect(result[9179]?.upload == 28330)
    }

    // MARK: - ProcessMonitor basic state

    @Test("ProcessMonitor initial state")
    func initialState() {
        let monitor = ProcessMonitor()
        #expect(monitor.topByCPU.isEmpty)
        #expect(monitor.topByMemory.isEmpty)
        #expect(monitor.topByNetwork.isEmpty)
        #expect(monitor.selfInfo == nil)
        #expect(monitor.isActive == false)
    }

    @Test("ProcessMonitor stop clears all state")
    func stopClearsState() {
        let monitor = ProcessMonitor()
        monitor.isActive = true
        monitor.stop()
        #expect(monitor.isActive == false)
        #expect(monitor.topByCPU.isEmpty)
        #expect(monitor.topByMemory.isEmpty)
        #expect(monitor.topByNetwork.isEmpty)
        #expect(monitor.selfInfo == nil)
    }
}
