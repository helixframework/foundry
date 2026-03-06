package com.helix.foundry.dashboard.api;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ServiceControlService {
  private final ServiceContainerResolver containerResolver;

  public ServiceControlService(ServiceContainerResolver containerResolver) {
    this.containerResolver = containerResolver;
  }

  public ServiceActionResponse restart(String serviceId) {
    String containerName = requireContainer(serviceId);
    ProcessBuilder builder = new ProcessBuilder("docker", "restart", containerName);
    builder.redirectErrorStream(true);

    try {
      Process process = builder.start();
      String output;
      try (BufferedReader reader = new BufferedReader(
          new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
        StringBuilder raw = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
          raw.append(line).append('\n');
        }
        output = raw.toString().trim();
      }

      int exitCode = process.waitFor();
      if (exitCode != 0) {
        throw new ResponseStatusException(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "Failed to restart " + serviceId + (output.isBlank() ? "" : ": " + output));
      }

      return new ServiceActionResponse(
          serviceId,
          "restart",
          "ok",
          output.isBlank() ? "Restart requested." : output);
    } catch (IOException | InterruptedException ex) {
      if (ex instanceof InterruptedException) {
        Thread.currentThread().interrupt();
      }
      throw new ResponseStatusException(
          HttpStatus.INTERNAL_SERVER_ERROR,
          "Unable to restart service: " + serviceId,
          ex);
    }
  }

  private String requireContainer(String serviceId) {
    String containerName = containerResolver.resolveContainerName(serviceId);
    if (containerName == null || containerName.isBlank()) {
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown service: " + serviceId);
    }
    return containerName;
  }
}
