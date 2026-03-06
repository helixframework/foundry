package com.helix.foundry.dashboard.api;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class ServiceLogsService {
  private final ServiceContainerResolver containerResolver;
  private final ExecutorService executor = Executors.newCachedThreadPool();

  public ServiceLogsService(ServiceContainerResolver containerResolver) {
    this.containerResolver = containerResolver;
  }

  public String tail(String serviceId, int tailLines) {
    String containerName = requireContainer(serviceId);
    int lines = normalizeTailLines(tailLines);

    ProcessBuilder builder = new ProcessBuilder(tailCommand(serviceId, containerName, lines));
    builder.redirectErrorStream(true);

    try {
      Process process = builder.start();
      StringBuilder output = new StringBuilder();
      try (BufferedReader reader = new BufferedReader(
          new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = reader.readLine()) != null) {
          output.append(line).append('\n');
        }
      }
      process.waitFor();
      return output.toString();
    } catch (IOException | InterruptedException ex) {
      if (ex instanceof InterruptedException) {
        Thread.currentThread().interrupt();
      }
      throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
          "Unable to read container logs", ex);
    }
  }

  public SseEmitter stream(String serviceId, int tailLines) {
    String containerName = requireContainer(serviceId);
    int lines = normalizeTailLines(tailLines);

    SseEmitter emitter = new SseEmitter(0L);
    AtomicReference<Process> processRef = new AtomicReference<>();

    Runnable destroyProcess = () -> {
      Process process = processRef.get();
      if (process != null && process.isAlive()) {
        process.destroy();
      }
    };

    emitter.onCompletion(destroyProcess);
    emitter.onTimeout(() -> {
      destroyProcess.run();
      emitter.complete();
    });

    executor.execute(() -> {
      ProcessBuilder builder = new ProcessBuilder(streamCommand(serviceId, containerName, lines));
      builder.redirectErrorStream(true);

      try {
        Process process = builder.start();
        processRef.set(process);

        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
          String line;
          while ((line = reader.readLine()) != null) {
            emitter.send(SseEmitter.event().name("line").data(line));
          }
        }

        emitter.complete();
      } catch (Exception ex) {
        try {
          emitter.send(SseEmitter.event().name("error").data("Log stream failed."));
          emitter.completeWithError(ex);
        } catch (Exception ignored) {
          emitter.complete();
        }
      } finally {
        destroyProcess.run();
      }
    });

    return emitter;
  }

  private int normalizeTailLines(int requestedTailLines) {
    if (requestedTailLines < 10) {
      return 10;
    }
    return Math.min(requestedTailLines, 5000);
  }

  private String requireContainer(String serviceId) {
    String containerName = containerResolver.resolveContainerName(serviceId);
    if (containerName == null || containerName.isBlank()) {
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown service: " + serviceId);
    }
    return containerName;
  }

  private String[] tailCommand(String serviceId, String containerName, int lines) {
    if ("teamcity".equals(serviceId)) {
      return new String[] {
          "docker",
          "exec",
          containerName,
          "sh",
          "-lc",
          "tail -n " + lines + " /opt/teamcity/logs/teamcity-server.log"
      };
    }

    return new String[] {"docker", "logs", "--tail", String.valueOf(lines), containerName};
  }

  private String[] streamCommand(String serviceId, String containerName, int lines) {
    if ("teamcity".equals(serviceId)) {
      return new String[] {
          "docker",
          "exec",
          containerName,
          "sh",
          "-lc",
          "tail -n " + lines + " -F /opt/teamcity/logs/teamcity-server.log"
      };
    }

    return new String[] {"docker", "logs", "-f", "--tail", String.valueOf(lines), containerName};
  }
}
