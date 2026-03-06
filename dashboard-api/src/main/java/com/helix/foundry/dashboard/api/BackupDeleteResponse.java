package com.helix.foundry.dashboard.api;

public record BackupDeleteResponse(
    String backupId,
    String status,
    String message
) {}
