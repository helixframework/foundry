package com.helix.foundry.dashboard.api;

import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/services")
public class ServiceControlController {
  private final ServiceControlService serviceControlService;

  public ServiceControlController(ServiceControlService serviceControlService) {
    this.serviceControlService = serviceControlService;
  }

  @PostMapping("/{serviceId}/restart")
  public ServiceActionResponse restart(@PathVariable String serviceId) {
    return serviceControlService.restart(serviceId);
  }
}
