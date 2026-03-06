package com.helix.foundry.dashboard.api;

import java.util.List;

public record BackupsResponse(
    String rootPath,
    boolean available,
    String statusMessage,
    int totalBackups,
    List<BackupCatalogEntry> backups,
    boolean backupInProgress
) {}
