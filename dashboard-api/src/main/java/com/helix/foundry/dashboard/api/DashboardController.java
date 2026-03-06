package com.helix.foundry.dashboard.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class DashboardController {
  private final DashboardService dashboardService;
  private final BackupCatalogService backupCatalogService;
  private final BackupSchedulerService backupSchedulerService;

  public DashboardController(
      DashboardService dashboardService,
      BackupCatalogService backupCatalogService,
      BackupSchedulerService backupSchedulerService) {
    this.dashboardService = dashboardService;
    this.backupCatalogService = backupCatalogService;
    this.backupSchedulerService = backupSchedulerService;
  }

  @GetMapping("/dashboard")
  public DashboardResponse getDashboard() {
    return dashboardService.buildDashboard();
  }

  @GetMapping("/backups")
  public BackupsResponse getBackups(@RequestParam(defaultValue = "30") int limit) {
    BackupsResponse response = backupCatalogService.catalog(limit);
    return new BackupsResponse(
        response.rootPath(),
        response.available(),
        response.statusMessage(),
        response.totalBackups(),
        response.backups(),
        backupSchedulerService.isBackupInProgress());
  }

  @PostMapping("/backups/run")
  public BackupRunResponse runBackupNow() {
    return backupSchedulerService.triggerBackupNow();
  }

  @DeleteMapping("/backups/{backupId}")
  public BackupDeleteResponse deleteBackup(@PathVariable String backupId) {
    return backupCatalogService.deleteBackup(backupId);
  }
}
