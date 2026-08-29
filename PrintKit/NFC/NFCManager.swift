import Foundation
import CoreNFC
import SwiftUI

/// Core NFC manager for user-owned writable NDEF tags.
///
/// PrintKit only reads and writes *your own* NDEF tags. It never attempts to
/// defeat, emulate, clone, unlock, or modify proprietary encrypted
/// manufacturer RFID/NFC systems.
@Observable
final class NFCManager: NSObject {
    enum ScanState: Equatable {
        case idle
        case ready
        case detected
        case reading
        case writing
        case verifying
        case complete
        case failed(String)
    }

    enum Mode: Equatable {
        case scanSpool
        case writeSpool(Spool)
        case readUtility
        case writeText(String)
        case writeURL(String)
        case erase
        case lock
    }

    private(set) var state: ScanState = .idle
    private(set) var detectedPayload: SpoolTagPayload?
    private(set) var utilityRecords: [String] = []
    private(set) var tagInfo: String = ""
    private(set) var lastError: String?

    var onSpoolScanned: ((SpoolTagPayload) -> Void)?
    var onWriteComplete: ((Bool) -> Void)?

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .scanSpool

    static var isAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    // MARK: - Public entry points

    func begin(mode: Mode) {
        self.mode = mode
        detectedPayload = nil
        utilityRecords = []
        lastError = nil

        guard Self.isAvailable else {
            // Simulator and unsupported hardware land here.
            state = .failed("NFC is not available on this device. NFC scanning requires a physical iPhone; use QR codes in the Simulator instead.")
            return
        }

        state = .ready
        // Keep Core NFC callbacks on the main queue. The manager is observed
        // directly by SwiftUI, so a background callback can otherwise leave
        // the UI showing a stale state (for example, "Preparing…" after a tag
        // has already been detected).
        let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        switch mode {
        case .scanSpool:
            session.alertMessage = "Hold the top of your iPhone near the spool tag."
        case .writeSpool:
            session.alertMessage = "Hold near the writable tag to write spool data."
        case .readUtility:
            session.alertMessage = "Hold near any NFC tag to inspect it."
        case .writeText, .writeURL:
            session.alertMessage = "Hold near a writable tag."
        case .erase:
            session.alertMessage = "Hold near the tag to erase its NDEF content."
        case .lock:
            session.alertMessage = "Hold near the tag to permanently lock it. This cannot be undone."
        }
        session.begin()
        self.session = session
    }

    func cancel() {
        session?.invalidate()
        session = nil
        state = .idle
    }

    // MARK: - Tag operations

    private func handle(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        state = .detected
        tag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            self.tagInfo = "Capacity ≈ \(capacity) bytes · \(status == .readWrite ? "Writable" : status == .readOnly ? "Read-only" : "Not NDEF-formatted")"

            switch self.mode {
            case .scanSpool, .readUtility:
                self.read(tag: tag, session: session)
            case .writeSpool(let spool):
                guard status == .readWrite else {
                    self.fail(session, status == .readOnly ? "This tag is read-only and cannot be written." : "This tag is not NDEF-formatted.")
                    return
                }
                self.writeSpool(spool, to: tag, session: session, capacity: capacity)
            case .writeText(let text):
                guard let payload = NFCNDEFPayload.wellKnownTypeTextPayload(
                    string: text,
                    locale: Locale(identifier: "en")
                ) else {
                    self.fail(session, "Could not encode the text for this NFC tag.")
                    return
                }
                self.writeSimple(payload: payload, to: tag, session: session, status: status)
            case .writeURL(let urlString):
                guard let url = URL(string: urlString) else {
                    self.fail(session, "Invalid URL.")
                    return
                }
                guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                    self.fail(session, "Could not encode the URL for this NFC tag.")
                    return
                }
                self.writeSimple(payload: payload, to: tag, session: session, status: status)
            case .erase:
                self.erase(tag: tag, session: session, status: status)
            case .lock:
                self.lock(tag: tag, session: session, status: status)
            }
        }
    }

    private func read(tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        state = .reading
        tag.readNDEF { [weak self] message, error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            guard let message, !message.records.isEmpty else {
                self.fail(session, "The tag contains no NDEF records.")
                return
            }

            self.utilityRecords = message.records.map { record in
                "TNF \(record.typeNameFormat.rawValue) · \(String(data: record.type, encoding: .utf8) ?? "binary") · \(record.payload.count) bytes"
            }

            for record in message.records {
                if let payload = SpoolTagPayload.decode(record.payload) {
                    self.detectedPayload = payload
                    self.state = .complete
                    Haptics.success()
                    session.alertMessage = "Spool tag found."
                    session.invalidate()
                    self.onSpoolScanned?(payload)
                    return
                }
            }

            if case .readUtility = self.mode {
                self.state = .complete
                Haptics.light()
                session.alertMessage = "Tag read. Not a 3DPrintKit spool tag."
                session.invalidate()
            } else {
                self.fail(session, "This is not a 3DPrintKit spool tag.")
            }
        }
    }

    private func writeSpool(_ spool: Spool, to tag: NFCNDEFTag, session: NFCNDEFReaderSession, capacity: Int) {
        let payload = SpoolTagPayload(spool: spool)
        guard let data = try? payload.encode() else {
            fail(session, "Could not encode the spool payload.")
            return
        }
        guard data.count <= capacity else {
            fail(session, "Payload is \(data.count) bytes but this tag only holds ≈ \(capacity) bytes.")
            return
        }

        state = .writing
        let record = NFCNDEFPayload(format: .unknown, type: Data(), identifier: Data(), payload: data)
        let message = NFCNDEFMessage(records: [record])

        tag.writeNDEF(message) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            // Read back to verify
            self.state = .verifying
            tag.readNDEF { [weak self] verifyMessage, error in
                guard let self else { return }
                if let error {
                    self.fail(session, "Write succeeded but verification failed: \(error.localizedDescription)")
                    return
                }
                let verified = verifyMessage?.records.contains { SpoolTagPayload.decode($0.payload)?.spoolID == spool.id } ?? false
                if verified {
                    self.state = .complete
                    Haptics.success()
                    session.alertMessage = "Tag written and verified."
                    session.invalidate()
                    self.onWriteComplete?(true)
                } else {
                    self.fail(session, "Verification failed: the tag does not contain the expected spool ID.")
                    self.onWriteComplete?(false)
                }
            }
        }
    }

    private func writeSimple(payload: NFCNDEFPayload, to tag: NFCNDEFTag, session: NFCNDEFReaderSession, status: NFCNDEFStatus) {
        guard status == .readWrite else {
            fail(session, "This tag is not writable.")
            return
        }
        state = .writing
        tag.writeNDEF(NFCNDEFMessage(records: [payload])) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            self.state = .complete
            Haptics.success()
            session.alertMessage = "Written."
            session.invalidate()
        }
    }

    private func erase(tag: NFCNDEFTag, session: NFCNDEFReaderSession, status: NFCNDEFStatus) {
        guard status == .readWrite else {
            fail(session, "This tag is not writable.")
            return
        }
        state = .writing
        tag.writeNDEF(NFCNDEFMessage(records: [])) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            self.state = .complete
            Haptics.success()
            session.alertMessage = "Tag erased."
            session.invalidate()
        }
    }

    private func lock(tag: NFCNDEFTag, session: NFCNDEFReaderSession, status: NFCNDEFStatus) {
        guard status == .readWrite else {
            fail(session, "Only writable tags can be locked.")
            return
        }
        state = .writing
        tag.writeLock { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, error.localizedDescription)
                return
            }
            self.state = .complete
            Haptics.warning()
            session.alertMessage = "Tag permanently locked."
            session.invalidate()
        }
    }

    private func fail(_ session: NFCNDEFReaderSession, _ message: String) {
        state = .failed(message)
        lastError = message
        Haptics.error()
        session.alertMessage = message
        session.invalidate()
    }
}

extension NFCManager: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not used: tag-based connection flow gives us write access too.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        if tags.count > 1 {
            session.alertMessage = "Multiple tags detected — hold the iPhone near a single tag."
        }
        session.connect(to: tag) { [weak self] error in
            if let error {
                self?.fail(session, error.localizedDescription)
                return
            }
            self?.handle(tag, session: session)
        }
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        state = .ready
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        // Code 200/201 = user canceled or session closed after success; don't flag as failure.
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            if state != .complete && state != .idle {
                state = .failed("The NFC scan ended before a readable 3DPrintKit tag was found. Tap Try Again and hold the top of the iPhone against the tag.")
            }
            return
        }
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorSessionTerminatedUnexpectedly.rawValue, state == .complete {
            return
        }
        if state != .complete && state != .idle {
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }
}
