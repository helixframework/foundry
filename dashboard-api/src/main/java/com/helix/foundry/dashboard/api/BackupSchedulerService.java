package com.helix.foundry.dashboard.api;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class BackupSchedulerService {
  private static final Logger logger = LoggerFactory.getLogger(BackupSchedulerService.class);
  private static final DateTimeFormatter BACKUP_TS_FORMATTER =
      DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");
  private final AtomicBoolean backupInProgress = new AtomicBoolean(false);

  @Value("${BACKUP_SCHEDULE_ENABLED:true}")
  private boolean backupScheduleEnabled;

  @Value("${BACKUP_WORKDIR:/workspace}")
  private String backupWorkdir;

  @Value("${BACKUP_OUTPUT_DIR:/workspace/backups}")
  private String backupOutputDir;

  @Value("${POSTGRES_CONTAINER_NAME:cicd-postgres}")
  private String postgresContainerName;

  @Value("${POSTGRES_ADMIN_USER:postgres}")
  private String postgresAdminUser;

  @Value("${GITEA_DB_NAME:gitea}")
  private String giteaDbName;

  @Value("${TEAMCITY_DB_NAME:teamcity}")
  private String teamcityDbName;

  @Scheduled(cron = "${BACKUP_CRON:0 0 2 * * *}")
  public void runScheduledBackup() {
    if (!backupScheduleEnabled) {
      return;
    }

    if (!startBackup("scheduled")) {
      logger.warn("Skipping scheduled backup because another backup is already running.");
    }
  }

  public BackupRunResponse triggerBackupNow() {
    if (!startBackup("manual")) {
      return new BackupRunResponse("busy", "Backup is already in progress.");
    }
    return new BackupRunResponse("started", "Backup started.");
  }

  public boolean isBackupInProgress() {
    return backupInProgress.get();
  }

  private boolean startBackup(String source) {
    if (!backupInProgress.compareAndSet(false, true)) {
      return false;
    }
    Thread backupThread =
        new Thread(() -> executeBackup(source), "backup-" + source + "-" + System.currentTimeMillis());
    backupThread.setDaemon(true);
    backupThread.start();
    return true;
  }

  private void executeBackup(String source) {
    Path workdir = Paths.get(backupWorkdir);
    Path backupRoot = Paths.get(backupOutputDir);
    String ts = BACKUP_TS_FORMATTER.format(LocalDateTime.now());
    Path backupDir = backupRoot.resolve(ts);
    Path pgDir = backupDir.resolve("postgres");
    try {
      logger.info("Starting {} backup in workdir {}", source, backupWorkdir);
      Files.createDirectories(pgDir);

      ensurePostgresRunning();
      dumpDatabase(giteaDbName, pgDir.resolve("gitea.dump"));
      dumpDatabase(teamcityDbName, pgDir.resolve("teamcity.dump"));
      createFilesArchive(workdir, backupDir.resolve("files.tar.gz"));
      copyEnvSnapshot(workdir, backupDir.resolve("env.snapshot"));
      writeMetadata(backupDir.resolve("metadata.txt"), ts);

      logger.info("{} backup completed successfully at {}", source, backupDir);
    } catch (Exception e) {
      if (e instanceof InterruptedException) {
        Thread.currentThread().interrupt();
      }
      logger.error("{} backup execution failed.", source, e);
      cleanupFailedBackup(backupDir);
    } finally {
      backupInProgress.set(false);
    }
  }

  private void ensurePostgresRunning() throws IOException, InterruptedException {
    int code = runCommand(List.of("docker", "start", postgresContainerName), Paths.get(backupWorkdir));
    if (code != 0) {
      throw new IOException("Failed to ensure postgres container is running.");
    }
  }

  private void dumpDatabase(String dbName, Path destination) throws IOException, InterruptedException {
    ProcessBuilder pb =
        new ProcessBuilder(
            "docker",
            "exec",
            "-i",
            postgresContainerName,
            "pg_dump",
            "-U",
            postgresAdminUser,
            "-d",
            dbName,
            "-Fc");
    pb.directory(Paths.get(backupWorkdir).toFile());
    pb.redirectOutput(destination.toFile());

    Process process = pb.start();
    try (BufferedReader stderr =
        new BufferedReader(new InputStreamReader(process.getErrorStream(), StandardCharsets.UTF_8))) {
      String line;
      while ((line = stderr.readLine()) != null) {
        logger.info("[scheduled-backup] {}", line);
      }
    }

    int exitCode = process.waitFor();
    if (exitCode != 0) {
      Files.deleteIfExists(destination);
      throw new IOException("pg_dump failed for database " + dbName);
    }
  }

  private void createFilesArchive(Path workdir, Path archivePath) throws IOException, InterruptedException {
    int code =
        runCommand(
            List.of(
                "tar",
                "--warning=no-file-changed",
                "--ignore-failed-read",
                "-czf",
                archivePath.toString(),
                "data/caddy",
                "data/gitea",
                "data/nexus",
                "data/teamcity",
                "dashboard-web",
                "caddy",
                "postgres/init"),
            workdir);
    if (code != 0) {
      throw new IOException("Failed to create files archive.");
    }
  }

  private void copyEnvSnapshot(Path workdir, Path destination) throws IOException {
    Path source = workdir.resolve(".env");
    if (Files.isRegularFile(source)) {
      Files.copy(source, destination, StandardCopyOption.REPLACE_EXISTING);
    }
  }

  private void writeMetadata(Path destination, String ts) throws IOException {
    String content =
        "created_at=" + ts + "\n"
            + "gitea_db=" + giteaDbName + "\n"
            + "teamcity_db=" + teamcityDbName + "\n";
    Files.writeString(destination, content, StandardCharsets.UTF_8);
  }

  private int runCommand(List<String> command, Path workdir) throws IOException, InterruptedException {
    ProcessBuilder pb = new ProcessBuilder(command);
    pb.directory(workdir.toFile());
    pb.redirectErrorStream(true);
    Process process = pb.start();
    try (BufferedReader reader =
        new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
      String line;
      while ((line = reader.readLine()) != null) {
        logger.info("[scheduled-backup] {}", line);
      }
    }
    return process.waitFor();
  }

  private void cleanupFailedBackup(Path backupDir) {
    if (!Files.exists(backupDir)) {
      return;
    }
    try (var walk = Files.walk(backupDir)) {
      walk.sorted(Comparator.reverseOrder())
          .forEach(path -> {
            try {
              Files.deleteIfExists(path);
            } catch (IOException ignored) {
              // Best effort cleanup only.
            }
          });
    } catch (IOException ignored) {
      // Best effort cleanup only.
    }
  }
}
