package com.helix.foundry.dashboard.api;

public record ServiceCard(
    String id,
    String name,
    String description,
    String url,
    String docsUrl,
    String status,
    ResourceUsage resourceUsage,
    ServiceCommands commands
) {
}
