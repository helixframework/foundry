package com.helix.foundry.dashboard.api;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class DashboardService {
  private static final DateTimeFormatter STARTED_AT_FORMATTER =
      DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss z").withZone(ZoneId.systemDefault());

  private final Instant startedAt = Instant.now();

  @Value("${FOUNDRY_ENVIRONMENT:local}")
  private String environment;

  @Value("${DASHBOARD_DOMAIN:localhost}")
  private String dashboardDomain;

  @Value("${GITEA_DOMAIN:gitea.localhost}")
  private String giteaDomain;

  @Value("${TEAMCITY_DOMAIN:teamcity.localhost}")
  private String teamcityDomain;

  @Value("${NEXUS_DOMAIN:nexus.localhost}")
  private String nexusDomain;

  @Value("${GITEA_CONTAINER_NAME:gitea}")
  private String giteaContainerName;

  @Value("${TEAMCITY_SERVER_CONTAINER_NAME:teamcity-server}")
  private String teamcityContainerName;

  @Value("${NEXUS_CONTAINER_NAME:nexus}")
  private String nexusContainerName;

  @Value("${BACKUPS_DIR:/backups}")
  private String backupsDir;

  @Value("${BACKUP_STALE_HOURS:24}")
  private int backupStaleHours;

  public DashboardResponse buildDashboard() {
    Map<String, ResourceUsage> usageByContainer =
        collectResourceUsage(List.of(giteaContainerName, teamcityContainerName, nexusContainerName));

    ServiceCard gitea =
        serviceCard(
            "gitea",
            "Gitea",
            "Git hosting and repository management",
            "https://" + giteaDomain,
            "https://docs.gitea.com/",
            "http://gitea:3000/",
            giteaContainerName,
            usageByContainer.getOrDefault(giteaContainerName, unavailableResourceUsage()));

    ServiceCard teamcity =
        serviceCard(
            "teamcity",
            "TeamCity",
            "Build server and pipeline orchestration",
            "https://" + teamcityDomain,
            "https://www.jetbrains.com/help/teamcity/",
            "http://teamcity-server:8111/",
            teamcityContainerName,
            usageByContainer.getOrDefault(teamcityContainerName, unavailableResourceUsage()));

    ServiceCard nexus =
        serviceCard(
            "nexus",
            "Nexus",
            "Artifact and repository management",
            "https://" + nexusDomain,
            "https://help.sonatype.com/en/nexus-repository-manager.html",
            "http://nexus:8081/",
            nexusContainerName,
            usageByContainer.getOrDefault(nexusContainerName, unavailableResourceUsage()));

    return new DashboardResponse(
        environment,
        "https://" + dashboardDomain,
        STARTED_AT_FORMATTER.format(startedAt),
        collectBackupStatus(),
        List.of(gitea, teamcity, nexus));
  }

  private ServiceCard serviceCard(
      String id,
      String name,
      String description,
      String url,
      String docsUrl,
      String probeUrl,
      String containerName,
      ResourceUsage resourceUsage) {
    String status = isHealthy(probeUrl) ? "Healthy" : "Starting";

    return new ServiceCard(
        id,
        name,
        description,
        url,
        docsUrl,
        status,
        resourceUsage,
        new ServiceCommands(
            "docker compose ps " + containerName,
            "docker compose logs -f " + containerName,
            "docker compose restart " + containerName));
  }

  private Map<String, ResourceUsage> collectResourceUsage(List<String> containerNames) {
    Map<String, ResourceUsage> usageByContainer = new HashMap<>();
    if (containerNames.isEmpty()) {
      return usageByContainer;
    }

    ProcessBuilder builder = new ProcessBuilder(statsCommand(containerNames));
    builder.redirectErrorStream(true);

    try {
      Process process = builder.start();
      try (BufferedReader reader = new BufferedReader(
          new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = reader.readLine()) != null) {
          parseStatsLine(line, usageByContainer);
        }
      }
      process.waitFor();
    } catch (IOException | InterruptedException ignored) {
      if (ignored instanceof InterruptedException) {
        Thread.currentThread().interrupt();
      }
      // Keep unavailable fallback values if docker stats cannot be read.
    }

    return usageByContainer;
  }

  private String[] statsCommand(List<String> containerNames) {
    String[] args = new String[5 + containerNames.size()];
    args[0] = "docker";
    args[1] = "stats";
    args[2] = "--no-stream";
    args[3] = "--format";
    args[4] = "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}";
    for (int i = 0; i < containerNames.size(); i++) {
      args[5 + i] = containerNames.get(i);
    }
    return args;
  }

  private void parseStatsLine(String line, Map<String, ResourceUsage> usageByContainer) {
    String[] parts = line.split("\\|", 3);
    if (parts.length < 3) {
      return;
    }

    String container = parts[0].trim();
    String cpu = parts[1].trim();
    String memory = parts[2].trim();
    if (container.isEmpty()) {
      return;
    }

    usageByContainer.put(
        container,
        new ResourceUsage(
            cpu.isEmpty() ? "N/A" : cpu,
            memory.isEmpty() ? "N/A" : memory));
  }

  private ResourceUsage unavailableResourceUsage() {
    return new ResourceUsage("N/A", "N/A");
  }

  private BackupStatus collectBackupStatus() {
    Path root = Paths.get(backupsDir);
    if (!Files.isDirectory(root)) {
      return new BackupStatus("N/A", "N/A", true, "Unhealthy");
    }

    try (Stream<Path> stream = Files.list(root)) {
      Path latestBackup = stream
          .filter(Files::isDirectory)
          .filter(path -> path.getFileName().toString().matches("\\d{8}-\\d{6}"))
          .sorted((a, b) -> b.getFileName().toString().compareTo(a.getFileName().toString()))
          .findFirst()
          .orElse(null);

      if (latestBackup == null) {
        return new BackupStatus("N/A", "N/A", true, "Unhealthy");
      }

      Instant backupInstant = Files.getLastModifiedTime(latestBackup).toInstant();
      Duration age = Duration.between(backupInstant, Instant.now());
      if (age.isNegative()) {
        age = Duration.ZERO;
      }

      long ageHours = age.toHours();
      long totalBytes = directorySize(latestBackup);
      boolean stale = ageHours >= Math.max(1, backupStaleHours);

      String message = stale ? "Unhealthy" : "Healthy";

      return new BackupStatus(
          STARTED_AT_FORMATTER.format(backupInstant),
          formatBytes(totalBytes),
          stale,
          message);
    } catch (IOException ignored) {
      return new BackupStatus("N/A", "N/A", true, "Unhealthy");
    }
  }

  private long directorySize(Path path) {
    try (Stream<Path> walk = Files.walk(path)) {
      return walk
          .filter(Files::isRegularFile)
          .mapToLong(file -> {
            try {
              return Files.size(file);
            } catch (IOException ignored) {
              return 0L;
            }
          })
          .sum();
    } catch (IOException ignored) {
      return 0L;
    }
  }

  private String formatBytes(long bytes) {
    if (bytes < 1024) {
      return bytes + " B";
    }

    double kb = bytes / 1024.0;
    if (kb < 1024) {
      return String.format("%.1f KB", kb);
    }

    double mb = kb / 1024.0;
    if (mb < 1024) {
      return String.format("%.1f MB", mb);
    }

    double gb = mb / 1024.0;
    return String.format("%.2f GB", gb);
  }

  private boolean isHealthy(String url) {
    HttpURLConnection connection = null;
    try {
      connection = (HttpURLConnection) URI.create(url).toURL().openConnection();
      connection.setRequestMethod("GET");
      connection.setConnectTimeout(2000);
      connection.setReadTimeout(2000);
      int status = connection.getResponseCode();
      return status >= 200 && status < 500;
    } catch (Exception ignored) {
      return false;
    } finally {
      if (connection != null) {
        connection.disconnect();
      }
    }
  }
}
