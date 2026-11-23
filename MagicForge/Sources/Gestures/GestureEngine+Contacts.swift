import Foundation
import MFCore

/// Contact tracking: landing, movement, lifting, palm / resting classification.
extension GestureEngine {
    func trackIndex(for id: Int) -> Int? {
        for index in tracks.indices where tracks[index].id == id { return index }
        return nil
    }

    func updateContacts(_ frame: TouchFrame, now: TimeInterval, afterGap: Bool, out: inout [GestureEvent]) {
        for index in tracks.indices { tracks[index].seen = false }

        // 1. Refresh contacts we already track.
        for contact in frame.contacts {
            guard let index = trackIndex(for: contact.id) else { continue }
            if contact.isTouching {
                refresh(at: index, with: contact, now: now)
            } else if contact.phase == .cancelled {
                tracks[index].endedCancelled = true
            }
        }
        // 2. Lifts: explicit `.ended` / `.cancelled`, or the contact simply vanished.
        var index = tracks.count - 1
        while index >= 0 {
            if !tracks[index].seen { lift(at: index, now: now, out: &out) }
            index -= 1
        }
        // 3. Landings (after lifts, so a finger swap in one frame is not a two-finger episode).
        for contact in frame.contacts where contact.isTouching && trackIndex(for: contact.id) == nil {
            land(contact, now: now, afterGap: afterGap, out: &out)
        }
        // 4. Resting-finger classification.
        for index in tracks.indices where tracks[index].role == .candidate {
            if isNowResting(tracks[index], now: now) { becomeResting(at: index, now: now, out: &out) }
        }
    }

    private func refresh(at index: Int, with contact: TouchContact, now: TimeInterval) {
        var track = tracks[index]
        let xMM = contact.x * table.widthMM, yMM = contact.y * table.heightMM
        let stepX = xMM - track.xMM, stepY = yMM - track.yMM
        track.pathMM += (stepX * stepX + stepY * stepY).squareRoot()
        track.x = contact.x; track.y = contact.y
        track.xMM = xMM; track.yMM = yMM
        track.minX = min(track.minX, contact.x); track.maxX = max(track.maxX, contact.x)
        track.minY = min(track.minY, contact.y); track.maxY = max(track.maxY, contact.y)
        let fromStartX = xMM - track.startXMM, fromStartY = yMM - track.startYMM
        track.maxDisplacementMM = max(track.maxDisplacementMM,
                                      (fromStartX * fromStartX + fromStartY * fromStartY).squareRoot())
        let fromAnchorX = xMM - track.anchorXMM, fromAnchorY = yMM - track.anchorYMM
        if fromAnchorX * fromAnchorX + fromAnchorY * fromAnchorY
            > EngineConstants.restRadiusMM * EngineConstants.restRadiusMM {
            track.anchorXMM = xMM; track.anchorYMM = yMM; track.anchorTime = now
        }
        track.maxSize = max(track.maxSize, contact.size)
        track.seen = true
        tracks[index] = track

        if track.isMember {
            episode.maxDisplacementMM = max(episode.maxDisplacementMM, track.maxDisplacementMM)
        }
        // Palm rejection only when the adapter reports sizes (size 0 = unknown).
        if track.role != .palm && contact.size > 0 && contact.size > table.palmSize {
            becomePalm(at: index)
        }
    }

    private func land(_ contact: TouchContact, now: TimeInterval, afterGap: Bool, out: inout [GestureEvent]) {
        var track = ContactTrack(contact: contact, now: now, widthMM: table.widthMM, heightMM: table.heightMM)
        if contact.size > 0 && contact.size > table.palmSize {
            track.role = .palm
        } else if afterGap && contact.phase != .began {
            // We do not know when this finger really landed.
            track.role = .quarantined
        } else {
            join(&track, now: now, out: &out)
        }
        tracks.append(track)
    }

    /// Decides how a newly landed finger relates to the current episode.
    private func join(_ track: inout ContactTrack, now: TimeInterval, out: inout [GestureEvent]) {
        if episode.phase != .idle {
            let inWindow = now <= episode.startTime + config.multiFingerLandingWindow
            if episode.phase == .tracking && !episode.liftedAny && inWindow {
                addMember(&track, now: now)
                return
            }
            if !membersAreQuiet(now: now) {
                // Late finger while the others are moving: the finger count changed mid-gesture.
                track.isMember = true
                episode.touching += 1
                if episode.phase == .tracking || episode.phase == .held { cancelEpisode("fingerCountChanged") }
                return
            }
            // The fingers already down are just sitting there: they are resting fingers and
            // must not block the newcomer.
            for index in tracks.indices where tracks[index].isMember {
                tracks[index].isMember = false
                tracks[index].role = .resting
            }
            episode = Episode()
            flushClaimedPending(now: now, out: &out)
        }
        episode = Episode()
        episode.phase = .tracking
        episode.startTime = now
        episode.moveStartTime = now
        if var tap = pending, !tap.claimed, now < tap.deadline {
            tap.claimed = true
            pending = tap
            episode.claimsPending = true
        }
        addMember(&track, now: now)
    }

    private func addMember(_ track: inout ContactTrack, now: TimeInterval) {
        track.isMember = true
        episode.peakCount += 1
        episode.touching += 1
        episode.lastLandTime = now
        episode.sumStartX += track.startX
        episode.sumStartY += track.startY
    }

    private func membersAreQuiet(now: TimeInterval) -> Bool {
        for track in tracks where track.isMember {
            let neverMoved = track.maxDisplacementMM <= config.holdMaxMovementMM
            let settled = now - track.anchorTime >= EngineConstants.quietDuration
            if !neverMoved && !settled { return false }
        }
        return true
    }

    private func lift(at index: Int, now: TimeInterval, out: inout [GestureEvent]) {
        let track = tracks.remove(at: index)
        guard track.isMember else { return }
        episode.touching -= 1
        episode.liftedAny = true
        if track.endedCancelled && (episode.phase == .tracking || episode.phase == .held) {
            cancelEpisode("contactCancelled")
        }
        if episode.touching <= 0 { finishEpisode(now: now, out: &out) }
    }

    private func isNowResting(_ track: ContactTrack, now: TimeInterval) -> Bool {
        let isFlat = track.maxSize > 0 && track.maxSize >= table.flatSize
        let needed = isFlat ? min(EngineConstants.flatRestDuration, config.restingFingerDuration)
                            : config.restingFingerDuration
        guard now - track.anchorTime >= needed else { return false }
        // After a hold fired the finger gets `sequenceWindow` to start a hold-then-swipe.
        if track.isMember && episode.phase == .held && now < episode.holdTime + config.sequenceWindow {
            return false
        }
        return true
    }

    private func becomeResting(at index: Int, now: TimeInterval, out: inout [GestureEvent]) {
        tracks[index].role = .resting
        removeMember(at: index, now: now, out: &out)
    }

    private func becomePalm(at index: Int) {
        tracks[index].role = .palm
        guard tracks[index].isMember else { return }
        tracks[index].isMember = false
        episode.touching -= 1
        if episode.touching <= 0 {
            // Nothing left to track; a tap waiting on this episode is released by
            // `resolveClaimedPending` at the end of the frame.
            episode = Episode()
        } else {
            cancelEpisode("palm")
        }
    }

    private func removeMember(at index: Int, now: TimeInterval, out: inout [GestureEvent]) {
        guard tracks[index].isMember else { return }
        tracks[index].isMember = false
        episode.touching -= 1
        if episode.touching <= 0 {
            episode = Episode()
            flushClaimedPending(now: now, out: &out)
        } else {
            episode.liftedAny = true
        }
    }

    func cancelEpisode(_ reason: String) {
        episode.phase = .cancelled
        episode.cancelReason = reason
    }
}
