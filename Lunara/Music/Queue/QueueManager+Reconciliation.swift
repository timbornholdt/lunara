import Foundation

@MainActor
extension QueueManager {
    func reconcile(removingTrackIDs invalidTrackIDs: Set<String>) {
        guard !invalidTrackIDs.isEmpty else { return }
        guard !items.isEmpty else { return }

        let originalItems = items
        let originalCurrentIndex = currentIndex

        var filteredItems: [QueueItem] = []
        filteredItems.reserveCapacity(originalItems.count)
        var oldToNewIndices: [Int: Int] = [:]
        oldToNewIndices.reserveCapacity(originalItems.count)

        for (index, item) in originalItems.enumerated() where !invalidTrackIDs.contains(item.trackID) {
            oldToNewIndices[index] = filteredItems.count
            filteredItems.append(item)
        }

        guard filteredItems.count != originalItems.count else { return }
        guard !filteredItems.isEmpty else {
            clear()
            return
        }

        applyReconciledItems(filteredItems)
        pendingSeekAfterNextPlay = nil

        guard let originalCurrentIndex else {
            persistQueueState(elapsed: lastPersistedElapsed)
            return
        }

        if let mappedCurrentIndex = oldToNewIndices[originalCurrentIndex] {
            applyReconciledCurrentIndex(mappedCurrentIndex)
            persistQueueState(elapsed: engine.elapsed)
            return
        }

        for candidateIndex in (originalCurrentIndex + 1)..<originalItems.count {
            guard let mappedCandidate = oldToNewIndices[candidateIndex] else { continue }
            applyReconciledCurrentIndex(mappedCandidate)
            playCurrentItem()
            return
        }

        applyReconciledCurrentIndex(nil)
        lastPersistedElapsed = 0
        engine.stop()
        persistQueueState(elapsed: 0)
    }
}
