package com.helix.foundry.dashboard.api;

public record BackupStatus(
    String latestBackupAt,
    String latestBackupSize,
    boolean stale,
    String statusMessage
) {
}
