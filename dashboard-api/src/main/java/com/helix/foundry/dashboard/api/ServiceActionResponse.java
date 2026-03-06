package com.helix.foundry.dashboard.api;

public record ServiceActionResponse(
    String serviceId,
    String action,
    String status,
    String message
) {
}
