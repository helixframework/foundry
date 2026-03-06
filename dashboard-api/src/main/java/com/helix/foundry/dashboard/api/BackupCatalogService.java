package com.helix.foundry.dashboard.api;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class BackupCatalogService {
  private static final DateTimeFormatter STARTED_AT_FORMATTER =
      DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss z").withZone(ZoneId.systemDefault());

  @Value("${BACKUPS_DIR:/backups}")
  private String backupsDir;

  public BackupsResponse catalog(int limit) {
    Path root = Paths.get(backupsDir);
    if (!Files.isDirectory(root)) {
      return new BackupsResponse(
          root.toAbsolutePath().toString(),
          false,
          "Backups directory is unavailable.",
          0,
          List.of(),
          false);
    }

    int safeLimit = Math.min(250, Math.max(1, limit));
    try (Stream<Path> stream = Files.list(root)) {
      List<Path> sortedDirs = stream
          .filter(Files::isDirectory)
          .filter(path -> path.getFileName().toString().matches("\\d{8}-\\d{6}"))
          .sorted(Comparator.comparing((Path p) -> p.getFileName().toString()).reversed())
          .toList();

      List<Path> completeDirs = sortedDirs.stream().filter(this::isCompleteBackup).toList();
      int incompleteCount = sortedDirs.size() - completeDirs.size();

      List<BackupCatalogEntry> backups = completeDirs.stream()
          .limit(safeLimit)
          .map(this::toEntry)
          .toList();

      String status;
      if (completeDirs.isEmpty()) {
        status = incompleteCount > 0 ? "No completed backups found." : "No backups found.";
      } else {
        status = "Backups available.";
      }

      return new BackupsResponse(
          root.toAbsolutePath().toString(),
          true,
          status,
          completeDirs.size(),
          backups,
          false);
    } catch (IOException ignored) {
      return new BackupsResponse(
          root.toAbsolutePath().toString(),
          false,
          "Unable to read backups directory.",
          0,
          List.of(),
          false);
    }
  }

  public BackupDeleteResponse deleteBackup(String backupId) {
    if (backupId == null || !backupId.matches("\\d{8}-\\d{6}")) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid backup id.");
    }

    Path root = Paths.get(backupsDir).toAbsolutePath().normalize();
    Path target = root.resolve(backupId).normalize();
    if (!target.startsWith(root)) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid backup path.");
    }
    if (!Files.isDirectory(target)) {
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Backup not found.");
    }

    try (Stream<Path> walk = Files.walk(target)) {
      List<Path> paths = walk.sorted(Comparator.reverseOrder()).toList();
      for (Path path : paths) {
        Files.deleteIfExists(path);
      }
    } catch (IOException ex) {
      throw new ResponseStatusException(
          HttpStatus.INTERNAL_SERVER_ERROR,
          "Unable to delete backup: " + ex.getMessage(),
          ex);
    }

    return new BackupDeleteResponse(backupId, "deleted", "Backup deleted.");
  }

  private BackupCatalogEntry toEntry(Path backupDir) {
    String id = backupDir.getFileName().toString();
    String createdAt = "Unknown";
    try {
      createdAt = STARTED_AT_FORMATTER.format(Files.getLastModifiedTime(backupDir).toInstant());
    } catch (IOException ignored) {
      // Keep fallback value if metadata cannot be read.
    }

    long sizeBytes = directorySize(backupDir);
    long fileCount = directoryFileCount(backupDir);
    return new BackupCatalogEntry(
        id,
        createdAt,
        sizeBytes,
        formatBytes(sizeBytes),
        fileCount);
  }

  private boolean isCompleteBackup(Path backupDir) {
    return Files.isRegularFile(backupDir.resolve("files.tar.gz"))
        && Files.isRegularFile(backupDir.resolve("metadata.txt"))
        && Files.isRegularFile(backupDir.resolve("postgres").resolve("gitea.dump"))
        && Files.isRegularFile(backupDir.resolve("postgres").resolve("teamcity.dump"));
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

  private long directoryFileCount(Path path) {
    try (Stream<Path> walk = Files.walk(path)) {
      return walk.filter(Files::isRegularFile).count();
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
}
