package com.helix.foundry.dashboard.api;

public record BackupCatalogEntry(
    String id,
    String createdAt,
    long sizeBytes,
    String sizeLabel,
    long fileCount
) {}
