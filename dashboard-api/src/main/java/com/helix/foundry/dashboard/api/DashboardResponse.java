package com.helix.foundry.dashboard.api;

import java.util.List;

public record DashboardResponse(
    String environment,
    String foundryVersion,
    String dashboardUrl,
    String startedAt,
    BackupStatus backupStatus,
    List<ServiceCard> services
) {
}
