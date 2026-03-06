package com.helix.foundry.dashboard.api;

public record ServiceCommands(
    String status,
    String logs,
    String restart
) {
}
