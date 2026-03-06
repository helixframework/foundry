package com.helix.foundry.dashboard.api;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/services")
public class ServiceLogsController {
  private final ServiceLogsService serviceLogsService;

  public ServiceLogsController(ServiceLogsService serviceLogsService) {
    this.serviceLogsService = serviceLogsService;
  }

  @GetMapping(value = "/{serviceId}/logs", produces = MediaType.TEXT_PLAIN_VALUE)
  public String tailLogs(
      @PathVariable String serviceId,
      @RequestParam(defaultValue = "200") int tail) {
    return serviceLogsService.tail(serviceId, tail);
  }

  @GetMapping(value = "/{serviceId}/logs/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
  public SseEmitter streamLogs(
      @PathVariable String serviceId,
      @RequestParam(defaultValue = "200") int tail) {
    return serviceLogsService.stream(serviceId, tail);
  }
}
